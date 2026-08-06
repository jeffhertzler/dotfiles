import {
  getAgentDir,
  type ExtensionAPI,
  type ExtensionContext,
} from "@earendil-works/pi-coding-agent";
import { builtinProviders } from "@earendil-works/pi-ai/providers/all";
import type { Api, Model, Provider } from "@earendil-works/pi-ai";
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
  providers?: string[];
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
    const associatedProviders = value.providers === undefined ? [] : value.providers;
    if (!Array.isArray(associatedProviders)) {
      throw new Error(`${CONFIG_PATH}: profiles.${name}.providers must be an array`);
    }
    const profileProviders = [
      provider,
      ...associatedProviders.map((candidate, index) =>
        requireNonEmptyString(candidate, `profiles.${name}.providers[${index}]`),
      ),
    ];
    if (new Set(profileProviders).size !== profileProviders.length) {
      throw new Error(`${CONFIG_PATH}: profile ${name} assigns a provider more than once`);
    }
    for (const profileProvider of profileProviders) {
      if (providers.has(profileProvider)) {
        throw new Error(
          `${CONFIG_PATH}: provider ${profileProvider} is assigned to multiple profiles`,
        );
      }
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
      providers: profileProviders.slice(1),
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
    for (const profileProvider of profileProviders) providers.add(profileProvider);
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

function cloneProvider(pi: ExtensionAPI, name: string, profile: ProfileDefinition): void {
  if (!profile.cloneFrom) return;

  const source = builtinProviders().find((provider) => provider.id === profile.cloneFrom);
  if (!source) throw new Error(`Cannot clone provider ${profile.cloneFrom} for profile ${name}`);

  const models = source.getModels().map((model) => ({
    ...model,
    provider: profile.provider,
    name: `${model.name || model.id} (${name})`,
  }));
  const provider: Provider = {
    id: profile.provider,
    name: `${source.name} (${name})`,
    baseUrl: source.baseUrl,
    headers: source.headers,
    auth: source.auth,
    getModels: () => models,
    stream: (model, context, options) => source.stream(model, context, options),
    streamSimple: (model, context, options) => source.streamSimple(model, context, options),
  };

  pi.registerProvider(provider);
}

function findProviderProfile(
  entries: ProfileEntry[],
  provider: string | undefined,
): ProfileEntry | undefined {
  if (provider === undefined) return undefined;
  return entries.find(
    ([, profile]) =>
      profile.provider === provider || profile.providers?.includes(provider) === true,
  );
}

function updateProfileState(entries: ProfileEntry[], provider: string | undefined): void {
  const state = globalThis as Record<PropertyKey, unknown>;
  const entry = findProviderProfile(entries, provider);
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

function parseCommandArgs(args: string): {
  profileName?: string;
  saveForProject: boolean;
} {
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
  let switchingProfiles = false;
  let revertingModel = false;
  for (const [name, profile] of entries) cloneProvider(pi, name, profile);

  pi.registerCommand("profile", {
    description: "Switch locked profiles; add --project to save the choice for this repository",
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

        switchingProfiles = true;
        let model: Model<Api> | undefined;
        try {
          model = await activateProfile(pi, config, profileName, ctx);
        } finally {
          switchingProfiles = false;
        }
        if (model && command.saveForProject) saveProjectProfile(profileName, model, ctx);
      } catch (error) {
        const message = error instanceof Error ? error.message : String(error);
        ctx.ui.notify(message, "error");
      }
    },
  });

  pi.on("session_start", (_event, ctx) => {
    updateProfileState(entries, ctx.model?.provider);
  });
  pi.on("model_select", async (event, ctx) => {
    if (switchingProfiles || revertingModel || event.source === "restore") {
      updateProfileState(entries, event.model.provider);
      return;
    }

    const previousProfile = findProviderProfile(entries, event.previousModel?.provider);
    const nextProfile = findProviderProfile(entries, event.model.provider);
    if (previousProfile && previousProfile[0] !== nextProfile?.[0] && event.previousModel) {
      const target = nextProfile?.[0] ?? "unassigned";
      ctx.ui.notify(
        `Blocked ${event.model.provider}: ${target} provider while profile is ${previousProfile[0]}. Use /profile ${target} to switch profiles.`,
        "warning",
      );
      revertingModel = true;
      try {
        await pi.setModel(event.previousModel);
      } finally {
        revertingModel = false;
      }
      return;
    }

    updateProfileState(entries, event.model.provider);
  });
  pi.on("session_shutdown", (event) => {
    if (event.reason === "quit") updateProfileState(entries, undefined);
  });
}
