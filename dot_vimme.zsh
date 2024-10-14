vldbdump() {
  ssh "${VIMME_USER}@${VIMME_SERVER} mysqldump --add-drop-database -u ${VIMME_DB_USER} -p${VIMME_DB_PASS} --databases ${VIMME_DB_NAME}" > "${1:-vimme.dump}"
}
vmdbdump() {
  ssh "${MATHBOTS_USER}@${MATHBOTS_SERVER} mysqldump --add-drop-database -u ${MATHBOTS_DB_USER} -p${MATHBOTS_DB_PASS} --databases ${MATHBOTS_DB_NAME}" > "${1:-mathbots.dump}"
}

vldbimport() {
  sed -i "s/`${VIMME_DB_NAME}`/`laravel`/g" "${1:-vimme.dump}"
  mysql -h 0.0.0.0 -P 33060 -ppassword -u sail laravel < "${1:-vimme.dump}"
}
vmdbimport() {
  sed -i "s/`${MATHBOTS_DB_NAME}`/`laravel`/g" "${1:-mathbots.dump}"
  mysql -h 0.0.0.0 -P 33061 -psecret -u sail laravel < "${1:-mathbots.dump}"
}

vldbimportlive() {
  ssh "${VIMME_USER}@${VIMME_SERVER} mysql -u ${VIMME_DB_USER} -p${VIMME_DB_PASS}" < "${1:-vimme.dump}"
}
vmdbimportlive() {
  ssh "${MATHBOTS_USER}@${MATHBOTS_SERVER} mysql -u ${MATHBOTS_DB_USER} -p${MATHBOTS_DB_PASS}" < "${1:-mathbots.dump}"
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
