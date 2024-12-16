bold=$(tput bold)
normal=$(tput sgr0)

if [ -f $HOME/greenlight-local.env ]; then
  export $( grep -vE "^(#.*|\s*)$" $HOME/greenlight-local.env )
fi

GG="$HOME/dev/greenlight"

export GG_BANNER_LEVEL="accent"
export GGREPOSERVICE="$GG/services/repo" # for compat with other scripts
export GGLEGACYPROXYSERVICE="$GG/gateways/legacy"
export GG_NOTIFICATION_SERVICE="$GG/services/notification"
export POLICY_DIR="$GG/authz/resources" # for repo svc to know where authz is
export LOGBACK_APPENDER="pretty"

abbrev-alias -c cdgg="cd $GG"

gggm() {
  cd "$GG/local"
  git config --global user.email jeff.hertzler@greenlight.guru
  ./gg.sh "good morning"
  git config --global user.email jeffhertzler@gmail.com
}

gg() { (cd "$GG/local" && ./gg.sh $@) }

ggd() { (cd "$GG/local" && ./docker.sh $@) }
ggsa() { (cd "$GG/local" && ./docker.sh stop-all) }
ggsrp() { (cd "$GG/local" && ./docker.sh start-repo-plus) }

ggkey() { (gggm); source ~/.zshrc }
ggkeyr() { (BROWSER=/usr/bin/echo gggm); source ~/.zshrc }

ggpull() {
  # echo "pulling ${bold}auth${normal}..."
  # (cd "$GG/authn" && echo "${bold}$(git branch --show-current)${normal}" && git pull)
  # echo "pulling ${bold}ah${normal}..."
  # (cd "$GG/ah" && echo "${bold}$(git branch --show-current)${normal}" && git pull)
  # echo "pulling ${bold}authz${normal}..."
  # (cd "$GG/authz" && echo "${bold}$(git branch --show-current)${normal}" && git pull)
  echo "pulling ${bold}common/java${normal}..."
  (cd "$GG/common/java" && echo "${bold}$(git branch --show-current)${normal}" && git pull)
  echo "pulling ${bold}common/node${normal}..."
  (cd "$GG/common/node" && echo "${bold}$(git branch --show-current)${normal}" && git pull)
  # echo "pulling ${bold}grpc${normal}..."
  # (cd "$GG/grpc" && echo "${bold}$(git branch --show-current)${normal}" && git pull)
  echo "pulling ${bold}design-system${normal}..."
  (cd "$GG/design-system" && echo "${bold}$(git branch --show-current)${normal}" && git pull)
  echo "pulling ${bold}frontend/about${normal}..."
  (cd "$GG/frontend/about" && echo "${bold}$(git branch --show-current)${normal}" && git pull)
  echo "pulling ${bold}frontend/authn${normal}..."
  (cd "$GG/frontend/authn" && echo "${bold}$(git branch --show-current)${normal}" && git pull)
  echo "pulling ${bold}frontend/download-center${normal}..."
  (cd "$GG/frontend/download-center" && echo "${bold}$(git branch --show-current)${normal}" && git pull)
  echo "pulling ${bold}frontend/legacy${normal}..."
  (cd "$GG/frontend/legacy" && echo "${bold}$(git branch --show-current)${normal}" && git pull)
  echo "pulling ${bold}frontend/risk${normal}..."
  (cd "$GG/frontend/risk" && echo "${bold}$(git branch --show-current)${normal}" && git pull)
  echo "pulling ${bold}frontend/settings${normal}..."
  (cd "$GG/frontend/settings" && echo "${bold}$(git branch --show-current)${normal}" && git pull)
  echo "pulling ${bold}frontend/settings${normal}..."
  (cd "$GG/frontend/settings" && echo "${bold}$(git branch --show-current)${normal}" && git pull)
  echo "pulling ${bold}frontend/training${normal}..."
  (cd "$GG/frontend/training" && echo "${bold}$(git branch --show-current)${normal}" && git pull)
  echo "pulling ${bold}gateways/graphql${normal}..."
  (cd "$GG/gateways/graphql" && echo "${bold}$(git branch --show-current)${normal}" && git pull)
  echo "pulling ${bold}gateways/legacy${normal}..."
  (cd "$GG/gateways/legacy" && echo "${bold}$(git branch --show-current)${normal}" && git pull)
  echo "pulling ${bold}infra/github${normal}..."
  (cd "$GG/infra/github" && echo "${bold}$(git branch --show-current)${normal}" && git pull)
  echo "pulling ${bold}local${normal}..."
  (cd "$GG/local" && echo "${bold}$(git branch --show-current)${normal}" && git pull)
  # echo "pulling ${bold}services/identity${normal}..."
  # (cd "$GG/services/identity" && echo "${bold}$(git branch --show-current)${normal}" && git pull)
  # echo "pulling ${bold}services/org${normal}..."
  # (cd "$GG/services/org" && echo "${bold}$(git branch --show-current)${normal}" && git pull)
  echo "pulling ${bold}services/notification${normal}..."
  (cd "$GG/services/notification" && echo "${bold}$(git branch --show-current)${normal}" && git pull)
  # echo "pulling ${bold}servies/pdm${normal}..."
  # (cd "$GG/servies/pdm" && echo "${bold}$(git branch --show-current)${normal}" && git pull)
  echo "pulling ${bold}services/repo${normal}..."
  (cd "$GG/services/repo" && echo "${bold}$(git branch --show-current)${normal}" && git pull)
  # echo "pulling ${bold}services/risk${normal}..."
  # (cd "$GG/services/risk" && echo "${bold}$(git branch --show-current)${normal}" && git pull)
  # echo "pulling ${bold}services/routing${normal}..."
  # (cd "$GG/services/routing" && echo "${bold}$(git branch --show-current)${normal}" && git pull)
  echo "pulling ${bold}services/suppliers${normal}..."
  (cd "$GG/services/suppliers" && echo "${bold}$(git branch --show-current)${normal}" && git pull)
  echo "pulling ${bold}waffles${normal}..."
  (cd "$GG/waffles" && echo "${bold}$(git branch --show-current)${normal}" && git pull)
  echo "pulling ${bold}yeoman${normal}..."
  (cd "$GG/yeoman" && echo "${bold}$(git branch --show-current)${normal}" && git pull)
}
