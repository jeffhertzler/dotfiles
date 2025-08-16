VIMME="$HOME/dev/vimme"

abbrev-alias -c cdv="cd $VIMME"

vldbdump() {
  ssh "${VIMME_USER}@${VIMME_SERVER}" mysqldump --add-drop-database -u $VIMME_DB_USER -p$VIMME_DB_PASS --databases $VIMME_DB_NAME > "${1:-vimme.dump}"
}
vmdbdump() {
  ssh "${MATHBOTS_USER}@${MATHBOTS_SERVER}" mysqldump --add-drop-database -u $MATHBOTS_DB_USER -p$MATHBOTS_DB_PASS --databases $MATHBOTS_DB_NAME > "${1:-mathbots.dump}"
}

vldbimport() {
  sed -i "s/\`${VIMME_DB_NAME}\`/\`laravel\`/g" "${1:-vimme.dump}"
  mariadb -h 127.0.0.1 -P 33060 -ppassword -usail laravel < "${1:-vimme.dump}"
}
vmdbimport() {
  sed -i "s/\`${MATHBOTS_DB_NAME}\`/\`laravel\`/g" "${1:-mathbots.dump}"
  mariadb -h 127.0.0.1 -P 33061 -ppassword -usail laravel < "${1:-mathbots.dump}"
}

vldbimportlive() {
  ssh "${VIMME_USER}@${VIMME_SERVER}" mysql -u "${VIMME_DB_USER}" "-p${VIMME_DB_PASS}" forge < "${1:-vimme.dump}"
}
vmdbimportlive() {
  ssh "${MATHBOTS_USER}@${MATHBOTS_SERVER}" mysql -u "${MATHBOTS_DB_USER}" "-p${MATHBOTS_DB_PASS}" forge < "${1:-mathbots.dump}"
}

vlssh() {
  ssh "${VIMME_USER}@${VIMME_SERVER}" "$@"
}
vmssh() {
  ssh "${MATHBOTS_USER}@${MATHBOTS_SERVER}" "$@"
}

vlscp() {
  scp "$1" "${VIMME_USER}@${VIMME_SERVER}:${VIMME_SERVER}/storage/$2"
}
