import {
  getAgentDir,
  type ExtensionAPI,
  type ExtensionContext,
} from "@earendil-works/pi-coding-agent";
import { builtinProviders } from "@earendil-works/pi-ai/providers/all";
import type { Api, AuthEvent, AuthPrompt, Model, OAuthCredentials } from "@earendil-works/pi-ai";
import {
  existsSync,
  mkdirSync,
  readFileSync,
  renameSync,
  unlinkSync,
  writeFileSync,
} from "node:fs";
import { join } from "node:path";

interface ProfileDefinition {
  provider: string;
  cloneFrom?: string;
  model?: string;
  footer?: string;
}

interface ProfilesConfig {
  profiles: Record<string, ProfileDefinition>;
}

type ProfileEntry = [name: string, definition: ProfileDefinition];

const CONFIG_PATH = join(getAgentDir(), "profiles.json");
const PROFILE_STATE = Symbol.for("pi.active-profile");

type ExtensionOAuthCallbacks = Parameters<
  NonNullable<Parameters<ExtensionAPI["registerProvider"]>[1]["oauth"]>["login"]
>[0];

function isRecord(value: unknown): value is Record<string, unknown> {
  return typeof value === "object" && value !== null && !Array.isArray(value);
}

function requireNonEmptyString(value: unknown, field: string): string {
  if (typeof value !== "string" || value.trim().length === 0) {
    throw new Error(`${CONFIG_PATH}: ${field} must be a non-empty string`);
  }
  return value.trim();
}

function parseConfig(raw: string): ProfilesConfig {
  const parsed: unknown = JSON.parse(raw);
  if (!isRecord(parsed) || !isRecord(parsed.profiles)) {
    throw new Error(`${CONFIG_PATH}: expected a profiles object`);
  }

  const profiles: Record<string, ProfileDefinition> = {};
  const providers = new Set<string>();

  for (const [name, value] of Object.entries(parsed.profiles)) {
    requireNonEmptyString(name, "profile name");
    if (!isRecord(value)) throw new Error(`${CONFIG_PATH}: profile ${name} must be an object`);

    const provider = requireNonEmptyString(value.provider, `profiles.${name}.provider`);
    if (providers.has(provider)) {
      throw new Error(`${CONFIG_PATH}: provider ${provider} is assigned to multiple profiles`);
    }

    const cloneFrom =
      value.cloneFrom === undefined
        ? undefined
        : requireNonEmptyString(value.cloneFrom, `profiles.${name}.cloneFrom`);
    if (cloneFrom === provider) {
      throw new Error(`${CONFIG_PATH}: profile ${name} cannot clone a provider onto itself`);
    }

    profiles[name] = {
      provider,
      cloneFrom,
      model:
        value.model === undefined
          ? undefined
          : requireNonEmptyString(value.model, `profiles.${name}.model`),
      footer:
        value.footer === undefined
          ? undefined
          : requireNonEmptyString(value.footer, `profiles.${name}.footer`),
    };
    providers.add(provider);
  }

  if (Object.keys(profiles).length === 0) {
    throw new Error(`${CONFIG_PATH}: configure at least one profile`);
  }
  return { profiles };
}

function loadConfig(): ProfilesConfig {
  try {
    return parseConfig(readFileSync(CONFIG_PATH, "utf8"));
  } catch (error) {
    if (error instanceof Error && error.message.startsWith(CONFIG_PATH)) throw error;
    const message = error instanceof Error ? error.message : String(error);
    throw new Error(`${CONFIG_PATH}: ${message}`, { cause: error });
  }
}

async function promptOAuth(callbacks: ExtensionOAuthCallbacks, prompt: AuthPrompt): Promise<string> {
  if (prompt.type === "select") {
    const selected = await callbacks.onSelect?.({
      message: prompt.message,
      options: prompt.options.map((option) => ({ id: option.id, label: option.label })),
    });
    if (selected === undefined) throw new Error("OAuth login cancelled");
    return selected;
  }

  if (prompt.type === "manual_code" && callbacks.onManualCodeInput) {
    return callbacks.onManualCodeInput();
  }

  return callbacks.onPrompt({
    message: prompt.message,
    placeholder: prompt.placeholder,
    allowEmpty: prompt.type === "manual_code",
  });
}

function notifyOAuth(callbacks: ExtensionOAuthCallbacks, event: AuthEvent): void {
  if (event.type === "auth_url") {
    callbacks.onAuth({ url: event.url, instructions: event.instructions });
  } else if (event.type === "device_code") {
    callbacks.onDeviceCode?.({
      userCode: event.userCode,
      verificationUri: event.verificationUri,
      intervalSeconds: event.intervalSeconds,
      expiresInSeconds: event.expiresInSeconds,
    });
  } else if (event.type === "progress" || event.type === "info") {
    callbacks.onProgress?.(event.message);
  }
}

function asOAuthCredential(credentials: OAuthCredentials): OAuthCredentials & { type: "oauth" } {
  return { ...credentials, type: "oauth" };
}

function cloneOAuthProvider(pi: ExtensionAPI, name: string, profile: ProfileDefinition): void {
  if (!profile.cloneFrom) return;

  const sourceProvider = builtinProviders().find((provider) => provider.id === profile.cloneFrom);
  const sourceModels = sourceProvider?.getModels() as Model<Api>[] | undefined;
  const sourceOAuth = sourceProvider?.auth.oauth;
  const firstModel = sourceModels?.[0];

  if (!sourceOAuth || !firstModel) {
    throw new Error(`Cannot clone OAuth provider ${profile.cloneFrom} for profile ${name}`);
  }

  pi.registerProvider(profile.provider, {
    name: `${sourceOAuth.name} (${name})`,
    baseUrl: firstModel.baseUrl,
    api: firstModel.api,
    oauth: {
      name: `${sourceOAuth.name} (${name})`,
      login: (callbacks) =>
        sourceOAuth.login({
          signal: callbacks.signal,
          prompt: (prompt) => promptOAuth(callbacks, prompt),
          notify: (event) => notifyOAuth(callbacks, event),
        }),
      refreshToken: (credentials) => sourceOAuth.refresh(asOAuthCredential(credentials)),
      getApiKey: (credentials) => credentials.access,
    },
    models: sourceModels.map((model) => ({
      id: model.id,
      name: `${model.name || model.id} (${name})`,
      api: model.api,
      baseUrl: model.baseUrl,
      reasoning: model.reasoning,
      thinkingLevelMap: model.thinkingLevelMap,
      input: [...model.input],
      cost: model.cost,
      contextWindow: model.contextWindow,
      maxTokens: model.maxTokens,
      compat: model.compat,
    })),
  });
}

function updateProfileState(entries: ProfileEntry[], provider: string | undefined): void {
  const state = globalThis as Record<PropertyKey, unknown>;
  const entry = entries.find(([, profile]) => profile.provider === provider);
  if (entry) state[PROFILE_STATE] = entry[1].footer ?? entry[0];
  else delete state[PROFILE_STATE];
}

function findProfileModel(
  profile: ProfileDefinition,
  ctx: ExtensionContext,
): Model<Api> | undefined {
  const modelIds = [...new Set([ctx.model?.id, profile.model].filter((id) => id !== undefined))];
  for (const modelId of modelIds) {
    const model = ctx.modelRegistry.find(profile.provider, modelId);
    if (model) return model;
  }
  return undefined;
}

async function activateProfile(
  pi: ExtensionAPI,
  config: ProfilesConfig,
  profileName: string,
  ctx: ExtensionContext,
): Promise<Model<Api> | undefined> {
  const profile = config.profiles[profileName];
  if (!profile) {
    ctx.ui.notify(`Unknown profile: ${profileName}`, "warning");
    return undefined;
  }

  const model = findProfileModel(profile, ctx);
  if (!model) {
    ctx.ui.notify(`No model configured for profile ${profileName}`, "warning");
    return undefined;
  }

  if (!(await pi.setModel(model))) {
    ctx.ui.notify(`Log in first with /login ${profile.provider}`, "warning");
    return undefined;
  }

  ctx.ui.notify(`Using profile: ${profileName}`, "info");
  return model;
}

function writeJsonAtomically(path: string, value: unknown): void {
  const temporaryPath = `${path}.${process.pid}.tmp`;
  try {
    writeFileSync(temporaryPath, `${JSON.stringify(value, null, 2)}\n`, "utf8");
    renameSync(temporaryPath, path);
  } finally {
    if (existsSync(temporaryPath)) unlinkSync(temporaryPath);
  }
}

function saveProjectProfile(profileName: string, model: Model<Api>, ctx: ExtensionContext): void {
  const settingsDirectory = join(ctx.cwd, ".pi");
  const settingsPath = join(settingsDirectory, "settings.json");
  const parsed: unknown = existsSync(settingsPath)
    ? JSON.parse(readFileSync(settingsPath, "utf8"))
    : {};
  if (!isRecord(parsed)) throw new Error(`${settingsPath}: expected a JSON object`);

  const settings = parsed;
  settings.defaultProvider = model.provider;
  settings.defaultModel = model.id;
  mkdirSync(settingsDirectory, { recursive: true });
  writeJsonAtomically(settingsPath, settings);
  ctx.ui.notify(`Saved profile ${profileName} for this project`, "info");
}

function parseCommandArgs(args: string): { profileName?: string; saveForProject: boolean } {
  const tokens = args.trim().split(/\s+/).filter(Boolean);
  const saveForProject = tokens.includes("--project");
  const names = tokens.filter((token) => token !== "--project");
  if (
    names.length > 1 ||
    names[0]?.startsWith("--") ||
    tokens.filter((token) => token === "--project").length > 1
  ) {
    throw new Error("Usage: /profile [name] [--project]");
  }
  return { profileName: names[0], saveForProject };
}

export default function (pi: ExtensionAPI) {
  const config = loadConfig();
  const entries = Object.entries(config.profiles);
  for (const [name, profile] of entries) cloneOAuthProvider(pi, name, profile);

  pi.registerCommand("profile", {
    description: "Switch profiles; add --project to save the choice for this repository",
    handler: async (args, ctx) => {
      try {
        const command = parseCommandArgs(args);
        const profileName =
          command.profileName ??
          (await ctx.ui.select(
            "Profile",
            entries.map(([name]) => name),
          ));
        if (!profileName) return;

        const model = await activateProfile(pi, config, profileName, ctx);
        if (model && command.saveForProject) saveProjectProfile(profileName, model, ctx);
      } catch (error) {
        const message = error instanceof Error ? error.message : String(error);
        ctx.ui.notify(message, "error");
      }
    },
  });

  pi.on("session_start", (_event, ctx) => {
    updateProfileState(entries, ctx.model?.provider);
    ctx.ui.setStatus("profile", undefined);
  });
  pi.on("model_select", (event) => updateProfileState(entries, event.model.provider));
  pi.on("session_shutdown", (event) => {
    if (event.reason === "quit") updateProfileState(entries);
  });
}
