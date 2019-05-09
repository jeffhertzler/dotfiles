;;; Naming conventions:
;;
;;   my-...   public variables or non-interactive functions
;;   my--...  private anything (non-interactive), not safe for direct use
;;   my/...   an interactive function; safe for M-x or keybinding
;;   my//...  an interactive function for managing/maintaining the config
;;   my:...   an evil operator, motion or command
;;   my|...   hook function
;;   my*...   advising functions
;;   my@...   a hydra command
;;   ...!       a macro or function for configuration
;;   =...       an interactive command that starts an app module
;;   %...       functions used for in-snippet logic
;;   +...       Any of the above but part of a module, e.g. `+emacs-lisp|init-hook'

(defvar my--file-name-handler-alist file-name-handler-alist)
(unless (or after-init-time noninteractive)
  ;; One of the contributors to long startup times is the garbage collector,
  ;; so we up its memory threshold, temporarily. It is reset later in
  ;; `my|finalize'.
  (setq gc-cons-threshold 402653184
        gc-cons-percentage 0.6
        file-name-handler-alist nil))

;; (require 'package)
;; (setq package-enable-at-startup nil)
;; (add-to-list 'package-archives '("melpa" . "http://melpa.org/packages/"))
;; (add-to-list 'package-archives '("gnu" . "http://elpa.gnu.org/packages/"))
;; (add-to-list 'package-archives '("org" . "https://orgmode.org/elpa/"))
;; (package-initialize)

;; (unless (package-installed-p 'use-package)
;;   (package-refresh-contents)
;;   (package-install 'use-package))

;; Install straight.el package manager
(setq straight-check-for-modifications 'live)
(defvar bootstrap-version)
(let ((bootstrap-file
       (expand-file-name "straight/repos/straight.el/bootstrap.el" user-emacs-directory))
      (bootstrap-version 5))
  (unless (file-exists-p bootstrap-file)
    (with-current-buffer
        (url-retrieve-synchronously
         "https://raw.githubusercontent.com/raxod502/straight.el/develop/install.el"
         'silent 'inhibit-cookies)
      (goto-char (point-max))
      (eval-print-last-sexp)))
  (load bootstrap-file nil 'nomessage))

;; Setup straight.el with use-package
(straight-use-package 'use-package)
(setq straight-use-package-by-default t)

;; Minimal UI
(when blink-cursor-mode
  (blink-cursor-mode -1))
(when menu-bar-mode
  (menu-bar-mode -1))
(when scroll-bar-mode
  (scroll-bar-mode -1))
(when tool-bar-mode
  (tool-bar-mode -1))
(when tooltip-mode
  (tooltip-mode -1))

;; (require 'dired)

(global-auto-revert-mode 1)

;; set font
(set-face-attribute 'default nil :family "Operator Mono Ssm Lig")

;; MacOS tweaks
(add-to-list 'default-frame-alist '(ns-transparent-titlebar . t))
(add-to-list 'default-frame-alist '(ns-appearance . dark))
(setq
 mac-option-modifier 'meta
 mac-command-modifier 'super
 frame-title-format nil
 mac-use-title-bar nil
 ns-use-proxy-icon nil
 ns-use-native-fullscreen nil)

;; UTF-8 as the default coding system
(when (fboundp 'set-charset-priority)
  (set-charset-priority 'unicode))
(prefer-coding-system        'utf-8)
(set-terminal-coding-system  'utf-8)
(set-keyboard-coding-system  'utf-8)
(set-selection-coding-system 'utf-8)
(setq locale-coding-system   'utf-8)
(setq-default buffer-file-coding-system 'utf-8)

;; y/n instead of yes/no
(fset #'yes-or-no-p #'y-or-n-p)

;; defaults
(setq-default
 create-lockfiles nil
 fill-column 120
 indent-tabs-mode nil
 inhibit-startup-message t
 initial-scratch-message nil
 ring-bell-function #'ignore
 sentence-end-double-space nil
 vc-follow-symlinks t
 visible-bell nil
 save-interprogram-paste-before-kill t)

;; line numbers in prog and text mode
(add-hook 'prog-mode-hook
          (lambda () (setq display-line-numbers 'relative)))
(add-hook 'text-mode-hook
          (lambda () (setq display-line-numbers 'relative)))

;; Package `no-littering' changes the default paths for lots of
;; different packages, with the net result that the ~/.emacs.d folder
;; is much more clean and organized.
(use-package no-littering
  ;; :ensure t
  :config
  (setq
   auto-save-file-name-transforms `((".*" ,(no-littering-expand-var-file-name "auto-save/") t))
   custom-file (no-littering-expand-etc-file-name "custom.el")))

;; key bindings package
(use-package general
  ;; :ensure t
  :config
  (general-evil-setup)

  ;; esc from insert mode with "fd"
  (general-imap "f"
    (general-key-dispatch 'self-insert-command
      :timeout 0.25
      "d" 'evil-normal-state))

  ;; setup leader key definer
  (general-create-definer my:leader
    :states '(normal motion visual insert emacs)
    :keymaps 'override
    :prefix "SPC"
    :non-normal-prefix "C-SPC")

  (general-create-definer my:normal
    :states '(normal motion visual))

  (general-create-definer my:visual
    :states '(visual))

  (defun my/emacs-dotfile () (interactive) (find-file "~/.emacs.d/init.el"))
  (defun my/emacs-reload () (interactive) (load-file "~/.emacs.d/init.el"))

  (defun my/kill-other-buffers ()
    "Kill all other buffers."
    (interactive)
    (seq-each
     #'kill-buffer
     (delete (current-buffer) (seq-filter #'buffer-file-name (buffer-list)))))

  (defun my/visual-shift-left ()
    (interactive)
    (call-interactively 'evil-shift-left)
    (evil-normal-state)
    (evil-visual-restore))

  (defun my/visual-shift-right ()
    (interactive)
    (call-interactively 'evil-shift-right)
    (evil-normal-state)
    (evil-visual-restore))

  ;; leader key bindings
  (my:leader
    "" '(nil :wk "leader")

    "SPC" '(execute-extended-command :wk "M-x")

    "b" '(:ignore t :wk "buffer")
    "bb" '(switch-to-buffer :wk "buffers")
    "bd" '(kill-this-buffer :wk "delete")
    "bD" '(my/kill-other-buffers :wk "delete others")
    "bs" '(save-buffer :wk "save")

    "e" '(:ignore t :wk "error")

    "f" '(:ignore t :wk "file")

    "fe" '(:ignore t :wk "emacs")
    "ff" '(find-file :wk "find")
    "fed" '(my/emacs-dotfile :wk "dotfile")
    "fer" '(my/emacs-reload :wk "reload")

    "fs" '(save-buffer :wk "save")

    "g" '(:ignore t :wk "git")

    "h" '(help-command :wk "help")

    "m" '(:ignore t :wk "major")

    "o" '(:ignore t :wk "org")

    "p" '(:ignore t :wk "project")

    "q" '(:ignore t :wk "quit")
    "qq" '(save-buffers-kill-emacs :wk "quit")
    "qQ" '(kill-emacs :wk "quit!")

    "r" '(:ignore t :wk "resume")

    "s" '(:ignore t :wk "search")

    "t" '(:ignore t :wk "toggle")
    "tw" '(whitespace-mode :wk "whitespace")

    "u" '(universal-argument :wk "universal")

    "w" '(:ignore t :wk "window")
    "wF" '(make-frame :wk "new frame")
    "wl" '(windmove-right :wk "right")
    "wh" '(windmove-left :wk "left")
    "wk" '(windmove-up :wk "up")
    "wj" '(windmove-down :wk "down")

    "x" '(:ignore t :wk "text")
    "xl" '(:ignore t :wk "line")
    "xls" '(sort-lines :wk "sort"))

  (my:normal
    "j" 'evil-next-visual-line
    "k" 'evil-previous-visual-line
    "-" 'dired-jump
    ";" 'evil-ex
    ":" 'evil-repeat-find-char)

  (my:visual
    ">" 'my/visual-shift-right
    "<" 'my/visual-shift-left)

  (general-def
    "s-n" 'make-frame
    "s-w" 'delete-frame
    "s-s" 'save-buffer
    "s-c" 'kill-ring-save
    "s-x" 'kill-region
    "s-v" 'yank
    "s-q" 'save-buffers-kill-emacs
    "s-P" 'execute-extended-command
    "s-p" 'find-file
    "s-<return>" 'toggle-frame-fullscreen))

;; (use-package auto-package-update
;;   :ensure t
;;   :config
;;   (setq auto-package-update-delete-old-versions t
;;         auto-package-update-hide-results t
;;         auto-package-update-last-update-day-path (no-littering-expand-var-file-name ".last-package-update-day"))
;;   (my:leader
;;     "feu" '(auto-package-update-now :wk "update")))

;; (use-package org
;;   :ensure org-plus-contrib
;;   :init
;;   (setq
;;    org-log-done 'time
;;    org-agenda-files '("~/todo.org")
;;    org-todo-keywords '((sequence "todo(t)" "done(d)")))
;;   :config
;;   (my:leader
;;     "oa" '(org-agenda-list :wk "agenda")
;;     "oc" '(org-capture :wk "capture")
;;     "ol" '(org-store-link :wk "link"))
;;   (my:leader org-mode-map
;;     "mi" '(:ignore t :wk "insert")
;;     "mih" '(org-insert-heading: :wk "heading")
;;     "mil" '(org-insert-link :wk "link")
;;     "mis" '(org-insert-subheading: :wk "subheading")
;;     "ml" '(org-open-at-point :wk "link")
;;     "mt" '(org-todo :wk "todo")))

;; (use-package evil-org
;;   :after org
;;   :hook
;;   (org-mode . evil-org-mode)
;;   (evil-org-mode . (lambda () (evil-org-set-key-theme)))
;;   :config
;;   (require 'evil-org-agenda)
;;   (evil-org-agenda-set-keys))

(use-package exec-path-from-shell
  ;; :ensure t
  :init
  (setq exec-path-from-shell-check-startup-files nil)
  :config
  (exec-path-from-shell-initialize)
  (let ((gls (executable-find "gls")))
    (when gls
      (setq insert-directory-program gls
            dired-listing-switches "-aBhl --group-directories-first"))))

;; evil mode
(use-package evil
  ;; :ensure t
  :init
  ;; disable built in evil keybindings in favor of evil-collection
  (setq
   evil-kill-on-visual-paste nil
   evil-want-keybinding nil
   evil-want-Y-yank-to-eol t
   evil-want-C-u-scroll t)

  :config
  (evil-mode 1))

(use-package evil-better-visual-line
  ;; :ensure t
  :after evil
  :config
  (evil-better-visual-line-on))

(use-package evil-surround
  ;; :ensure t
  :after evil
  :config
  (global-evil-surround-mode 1))

;; evil keybindings for other packages
(use-package evil-collection
  ;; :ensure t
  :after evil
  :config
  (evil-collection-init))

;; code commenting
(use-package evil-commentary
  ;; :ensure t
  :after evil
  :hook
  (prog-mode . evil-commentary-mode))

;; theme
(use-package doom-themes
  ;; :ensure t
  :config
  (load-theme 'doom-dracula t)
  (doom-themes-treemacs-config)
  (doom-themes-org-config))

;; keybinding documentation
(use-package which-key
  ;; :ensure t
  :defer 1
  :init
  (setq which-key-separator " ")
  (setq which-key-prefix-prefix "+")
  :config
  (which-key-mode))

(defun my--ignore-dired-buffers (str)
  "Return non-nil if STR names a Dired buffer.
This function is intended for use with `ivy-ignore-buffers'."
  (let ((buf (get-buffer str)))
    (and buf (eq (buffer-local-value 'major-mode buf) 'dired-mode))))

;; completion
(use-package ivy
  ;; :ensure t
  :defer 1
  :init
  (setq
   ivy-re-builders-alist '((counsel-ag . ivy--regex))
   ivy-count-format "%d/%d ")

  :general
  ;; (my:normal "/" '(swiper :wk "search"))
  (my:leader
    "/" '(swiper-isearch :wk "search")
    "rl" '(ivy-resume :wk "last")
    "sf" '(swiper-isearch :wk "file"))

  :config
  ;; set bindings if minibuffer uses evil or not
  (general-def ivy-minibuffer-map
    "C-j" 'ivy-next-line
    "C-k" 'ivy-previous-line)

  (add-to-list 'ivy-ignore-buffers #'my--ignore-dired-buffers)

  (ivy-mode 1))

(use-package avy
  ;; :ensure t
  :defer 1
  :general
  (my:leader
    "fw" '(avy-goto-word-1 :wk "word")))

;; ivy specific versions of emacs commands
(use-package counsel
  ;; :ensure t
  :defer 1
  :config
  (counsel-mode 1))

(use-package wgrep
  :defer 1)

(defvar my--counsel-flycheck-history nil
  "History for `counsel-flycheck'")

(defun my/counsel-flycheck ()
  (interactive)
  (if (not (bound-and-true-p flycheck-mode))
      (message "Flycheck mode is not available or enabled")
    (ivy-read "Error: "
              (let ((source-buffer (current-buffer)))
                (with-current-buffer (or (get-buffer flycheck-error-list-buffer)
                                         (progn
                                           (with-current-buffer
                                               (get-buffer-create flycheck-error-list-buffer)
                                             (flycheck-error-list-mode)
                                             (current-buffer))))
                  (flycheck-error-list-set-source source-buffer)
                  (flycheck-error-list-reset-filter)
                  (revert-buffer t t t)
                  (split-string (buffer-string) "\n" t " *")))
              :action (lambda (s &rest _)
                        (-when-let* ( (error (get-text-property 0 'tabulated-list-id s))
                                      (pos (flycheck-error-pos error)) )
                          (goto-char (flycheck-error-pos error))))
              :history 'my--counsel-flycheck-history)))

;; completion
;; (use-package helm
;;   :defer 1
;;   :config
;;   (helm-mode 1)
;;   (general-def helm-map
;;     "C-j" 'helm-next-line
;;     "C-k" 'helm-previous-line)
;;   (general-def
;;     [remap find-file] 'helm-find-files
;;     [remap execute-extended-command] 'helm-M-x))

;; (use-package helm-rg
;;   :after helm
;;   :config
;;   (my:leader
;;     "sd" '(helm-rg :wk "directory")))

;;   (use-package helm-projectile
;;     :after helm
;;     :config
;;     (helm-projectile-on))

;;   (use-package helm-swoop
;;     :after helm
;;     :config
;;     (my:leader
;;       "/" '(helm-swoop :wk "search")
;;       "sf" '(helm-swoop :wk "file")))

;; code completion
(use-package company
  ;; :ensure t
  :hook
  (prog-mode . company-mode)
  :general
  (general-def
    "C-<return>" 'company-complete))

;; sorting and filtering
(use-package prescient
  ;; :ensure t
  :init
  ;; options: '(literal+initialism literal initialism regexp fuzzy)
  (setq prescient-filter-method 'literal+initialism)
  :config
  (prescient-persist-mode 1))

;; with ivy
(use-package ivy-prescient
  ;; :ensure t
  :after ivy prescient
  :config
  (ivy-prescient-mode 1))

(use-package ace-window
  ;; :ensure t
  :general
  (my:leader "ww" '(ace-window :wk "ace window")))

(use-package treemacs
  ;; :ensure t
  :general
  (my:leader "ft" '(treemacs :wk "tree")))

(use-package treemacs-evil
  ;; :ensure t
  :after treemacs evil)

(use-package treemacs-projectile
  ;; :ensure t
  :after treemacs projectile)

;; projects
(use-package projectile
  ;; :ensure t
  :general
  (my:leader "pb" '(projectile-switch-to-buffer :wk "buffer"))
  (my:leader "pf" '(projectile-find-file :wk "file"))
  (my:leader "pl" '(projectile-switch-project :wk "list"))
  (my:leader "ps" '(projectile-ripgrep :wk "search"))
  (my:leader "sp" '(projectile-ripgrep :wk "project"))
  :config
  (projectile-mode +1))

;; projects via counsel
(use-package counsel-projectile
  ;; :ensure t
  :config
  (counsel-projectile-mode))

(use-package rainbow-delimiters
  ;; :ensure t
  :hook
  (prog-mode . rainbow-delimiters-mode))

;; better undo
(use-package undo-tree
  ;; :ensure t
  :config
  (global-undo-tree-mode +1))

(use-package subword
  ;; :ensure t
  :general
  (my:leader "ts" '(subword-mode :wk "subword mode"))
  :hook
  (prog-mode . subword-mode))

(use-package doom-modeline
  ;; :ensure t
  :config
  (setq doom-modeline-buffer-file-name-style 'truncate-upto-root)
  (defun anzu--reset-status () )
  :hook (after-init . doom-modeline-init))

(use-package all-the-icons
  ;; :ensure t
  )

(use-package yasnippet
  ;; :ensure t
  :defer 1
  :init
  ;; don't give me init message
  (setq yas-verbosity 1)
  :config
  (yas-global-mode))

(use-package flycheck
  ;; :ensure t
  :hook
  (prog-mode . flycheck-mode)
  :config
  (my:leader
    ;; "el" '(flycheck-list-errors :wk "list")
    "el" '(my/counsel-flycheck :wk "list")
    "en" '(flycheck-next-error :wk "next")
    "ep" '(flycheck-previous-error :wk "previous")))

;; git ui
(use-package magit
  ;; :ensure t
  :general
  (my:leader "gs" '(magit-status :wk "status")))

(use-package magithub
  ;; :ensure t
  :straight (:host github :repo "mgcyung/magithub" :branch "transient")
  :after magit
  :config
  (magithub-feature-autoinject t)
  (setq magithub-clone-default-directory "~/dev"))

;; vim keybindings for magit
(use-package evil-magit
  ;; :ensure t
  :after evil magit)

;; emacs startup profiler
(use-package esup
  ;; :ensure t
  )

;; restart emacs
(use-package restart-emacs
  ;; :ensure t
  :general
  (my:leader "qr" '(restart-emacs :wk "restart emacs")))

;; indentation
(setq-default
 c-basic-offset 2
 css-indent-offset 2
 js-indent-level 2
 sh-basic-offset 2
 tab-width 2)

(use-package editorconfig
  ;; :ensure t
  :defer 1
  :config
  (editorconfig-mode 1))

(use-package lsp-mode
  ;; :ensure t
  :commands lsp
  ;; :init
  ;; (setq
  ;;  lsp-prefer-flymake nil
  ;;  lsp-response-timeout 100)
  :config
  (my:leader
    :keymaps 'lsp-mode-map
    "ml" '(:ignore t :wk "lsp")
    "mla" '(lsp-execute-code-action :wk "action")
    "mlR" '(lsp-restart-workspace :wk "restart")
    "mlf" '(:ignore t :wk "find")
    "mlfD" '(lsp-find-declaration :wk "declaration")
    "mlfd" '(lsp-find-definition :wk "definition")
    "mlfi" '(lsp-find-implementation :wk "implementation")
    "mlfr" '(lsp-find-references :wk "references")
    "mlft" '(lsp-find-type-definition :wk "type def")
    "mlr" '(lsp-rename :wk "rename"))
  (setq lsp-prefer-flymake nil)
  :hook
  ((css-mode scss-mode) . lsp))

(use-package lsp-ui
  ;; :ensure t
  :commands lsp-ui-mode
  :init
  (setq
   lsp-ui-imenu-enable nil
   lsp-ui-flycheck-enable t))

(use-package company-lsp
  ;; :ensure t
  :init
  (setq company-lsp-cache-candidates t))

;; ts
(use-package typescript-mode
  ;; :ensure t
  :mode "\\.ts\\'"
  :config
  (flycheck-add-mode 'javascript-eslint 'typescript-mode))


(use-package tide
  ;; :ensure t
  :after (company flycheck)
  :hook ((typescript-mode . tide-setup)
         (js2-mode . tide-setup)
         (typescript-mode . tide-hl-identifier-mode)
         (js2-mode . tide-hl-identifier-mode))
  :config
  (flycheck-add-next-checker 'javascript-eslint 'javascript-tide 'append)
  (flycheck-add-next-checker 'typescript-tide 'javascript-eslint 'append)
  (my:leader
    :keymaps 'tide-mode-map
    "mt" '(:ignore t :wk "tide")
    "mtd" '(tide-documentation-at-point :wk "documentation")
    "mta" '(:ignore t :wk "actions")
    "mtaf" '(tide-fix :wk "fix")
    "mtar" '(tide-refactor :wk "refactor")
    "mtf" '(:ignore t :wk "find")
    "mtfd" '(tide-jump-to-definition :wk "definition")
    "mtfi" '(tide-jump-to-implementation :wk "implementation")
    "mtft" '((lambda () (interactive) (tide-jump-to-definition t)) :wk "type def")
    "mtfr" '(tide-references :wk "references")
    "mtr" '(:ignore t :wk "rename")
    "mtrf" '(tide-rename-file :wk "file")
    "mtrs" '(tide-rename-symbol :wk "symbol")
    "mtR" '(tide-restart-server :wk "restart")))

;; js
(use-package js2-mode
  ;; :ensure t
  :mode "\\.js\\'"
  :interpreter "node"
  :config
  (setq
   js2-mode-show-parse-errors nil
   js2-mode-show-strict-warnings nil))

(use-package js2-refactor
  ;; :ensure t
  :hook
  (js2-mode . js2-refactor-mode)
  :config
  (my:leader
    :keymaps 'js2-refactor-mode-map
    "mr" '(:ignore t :wk "refactor")
    "mre" '(:ignore t :wk "extract")
    "mrec" '(js2r-extract-const :wk "const")
    "mref" '(js2r-extract-function :wk "function")
    "mrel" '(js2r-extract-let :wk "let")
    "mrem" '(js2r-extract-method :wk "method")
    "mrev" '(js2r-extract-var :wk "var")
    "mri" '(js2r-inline-var :wk "inline")
    "mrr" '(js2r-rename-var :wk "rename")
    "mrE" '(js2r-expand-node-at-point :wk "expand")
    "mrC" '(js2r-contract-node-at-point :wk "contract")))

(use-package graphql-mode
  ;; :ensure t
  :mode "\\.graphql\\'")

(use-package json-mode
  ;; :ensure t
  :mode "\\.json\\'")

(use-package web-mode
  ;; :ensure t
  :straight (:host github :repo "fxbois/web-mode" :fork (:host github :repo "jeffhertzler/web-mode"))
  :mode "\\.jsx\\'"
  :mode "\\.hbs\\'"
  :init
  (setq
   web-mode-comment-style 2
   web-mode-enable-current-element-highlight t))



(use-package fish-mode
  ;; :ensure t
  :mode "\\.fish\\'"
  )

(use-package sh-script
  :straight nil
  :init
  (add-hook 'sh-mode-hook
            (lambda () (setq evil-shift-width sh-basic-offset))))

(use-package add-node-modules-path
  ;; :ensure t
  :hook
  (js2-mode . add-node-modules-path)
  (json-mode . add-node-modules-path)
  (typescript-mode . add-node-modules-path)
  (web-mode . add-node-modules-path))

;; formatting
(use-package format-all
  ;; :ensure t
  :hook
  (emacs-lisp-mode . format-all-mode)
  (lisp-interaction-mode . format-all-mode)
  (js2-mode . format-all-mode)
  (json-mode . format-all-mode)
  (typescript-mode . format-all-mode)
  :config
  (my:leader
    "bf" '(format-all-buffer :wk "format")))

(use-package bool-flip
  :config
  (my:leader
    "tb" '(bool-flip-do-flip :wk "boolean")))

(use-package org-jira
  ;; :ensure t
  :init
  (setq jiralib-url "https://greenlightguru.atlassian.net")
  (setq org-jira-use-status-as-todo t)
  (setq org-jira-done-states '("Closed" "Resolved" "Done" "Ready For Deploy"))
  (setq org-jira-default-jql "status in (Approved, Backlog, \"In Code Review\", \"In Process\", \"In Progress\", Open, \"Ready for Deploy\", Reopened, \"Selected for Development\", \"User Story Mapping\") AND assignee in (currentUser()) ORDER BY status ASC, updated DESC"))

(use-package elcord)

;; reset
(defun my|finalize ()
  "Reset `gc-cons-threshold', `gc-cons-percentage' and `file-name-handler-alist'."
  (unless (or (not after-init-time) noninteractive)
    ;; If you forget to reset this, you'll get stuttering and random freezes!
    (setq
     gc-cons-threshold 16777216
     gc-cons-percentage 0.1
     file-name-handler-alist my--file-name-handler-alist)

    (when (display-graphic-p)
      (require 'server)
      (unless (server-running-p)
        (server-start))))

  (message "Emacs ready in %s with %d garbage collections."
           (format "%.2f seconds"
                   (float-time
                    (time-subtract after-init-time before-init-time)))
           gcs-done))

(add-hook 'emacs-startup-hook #'my|finalize)

;; Local Variables:
;; flycheck-disabled-checkers: (emacs-lisp emacs-lisp-checkdoc)
;; End:
