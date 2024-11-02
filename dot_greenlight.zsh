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

ggd() { (cd "$GG/local" && ./docker.sh $@) }
gg() { (cd "$GG/local" && ./gg.sh $@) }
ggkey() { (gggm); source ~/.zshrc }
ggkeyr() { (BROWSER=/usr/bin/echo gggm); source ~/.zshrc }
ggpull() {
  echo "pulling ${bold}auth${normal}..."
  (cd "$GG/authn" && echo "${bold}$(git branch --show-current)${normal}" && git pull)
  echo "pulling ${bold}ah${normal}..."
  (cd "$GG/ah" && echo "${bold}$(git branch --show-current)${normal}" && git pull)
  echo "pulling ${bold}authz${normal}..."
  (cd "$GG/authz" && echo "${bold}$(git branch --show-current)${normal}" && git pull)
  echo "pulling ${bold}common${normal}..."
  (cd "$GG/common" && echo "${bold}$(git branch --show-current)${normal}" && git pull)
  echo "pulling ${bold}grpc${normal}..."
  (cd "$GG/grpc" && echo "${bold}$(git branch --show-current)${normal}" && git pull)
  echo "pulling ${bold}local${normal}..."
  (cd "$GG/local" && echo "${bold}$(git branch --show-current)${normal}" && git pull)
  echo "pulling ${bold}org${normal}..."
  (cd "$GG/org" && echo "${bold}$(git branch --show-current)${normal}" && git pull)
  echo "pulling ${bold}repo${normal}..."
  (cd "$GG/repo" && echo "${bold}$(git branch --show-current)${normal}" && git pull)
  echo "pulling ${bold}risk${normal}..."
  (cd "$GG/risk" && echo "${bold}$(git branch --show-current)${normal}" && git pull)
  echo "pulling ${bold}pdm${normal}..."
  (cd "$GG/pdm" && echo "${bold}$(git branch --show-current)${normal}" && git pull)
  echo "pulling ${bold}routing${normal}..."
  (cd "$GG/routing" && echo "${bold}$(git branch --show-current)${normal}" && git pull)
  echo "pulling ${bold}identity${normal}..."
  (cd "$GG/identity" && echo "${bold}$(git branch --show-current)${normal}" && git pull)
  echo "pulling ${bold}graphql${normal}..."
  (cd "$GG/graphql" && echo "${bold}$(git branch --show-current)${normal}" && git pull)
  echo "pulling ${bold}legacy-proxy${normal}..."
  (cd "$GG/legacy-proxy" && echo "${bold}$(git branch --show-current)${normal}" && git pull)
  echo "pulling ${bold}notification${normal}..."
  (cd "$GG/notification" && echo "${bold}$(git branch --show-current)${normal}" && git pull)
  echo "pulling ${bold}legacy-frontend${normal}..."
  (cd "$GG/frontend/legacy" && echo "${bold}$(git branch --show-current)${normal}" && git pull)
  echo "pulling ${bold}risk-frontend${normal}..."
  (cd "$GG/frontend/risk" && echo "${bold}$(git branch --show-current)${normal}" && git pull)
  echo "pulling ${bold}design-system${normal}..."
  (cd "$GG/design-system" && echo "${bold}$(git branch --show-current)${normal}" && git pull)
  echo "pulling ${bold}node-common${normal}..."
  (cd "$GG/node-common" && echo "${bold}$(git branch --show-current)${normal}" && git pull)
}
