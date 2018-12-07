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
(blink-cursor-mode -1)
(menu-bar-mode -1)
(scroll-bar-mode -1)
(tool-bar-mode -1)
(tooltip-mode -1)

;; set font
(set-face-attribute 'default nil :family "Operator Mono Ssm Lig")

;; MacOS tweaks
(add-to-list 'default-frame-alist '(ns-transparent-titlebar . t))
(add-to-list 'default-frame-alist '(ns-appearance . dark))
(setq
 frame-title-format nil
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

  (defun my/emacs-dotfile () (interactive) (find-file "~/.emacs.d/init.el"))
  (defun my/emacs-reload () (interactive) (load-file "~/.emacs.d/init.el"))

  ;; leader key bindings
  (my:leader
    "" '(nil :wk "leader")

    "SPC" '(execute-extended-command :wk "M-x")

    "b" '(:ignore t :wk "buffer")
    "bb" '(switch-to-buffer :wk "buffers")
    "bd" '(kill-this-buffer :wk "delete")
    "bs" '(save-buffer :wk "save")

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

    "w" '(:ignore t :wk "window")
    "wl" '(windmove-right :wk "right")
    "wh" '(windmove-left :wk "left")
    "wk" '(windmove-up :wk "up")
    "wj" '(windmove-down :wk "down")

    "x" '(:ignore t :wk "text")
    "xl" '(:ignore t :wk "line")
    "xls" '(sort-lines :wk "sort"))

  (general-create-definer my:normal
    :states '(normal motion visual))

  (my:normal
    "j" 'evil-next-visual-line
    "k" 'evil-previous-visual-line
    "-" 'dired-jump
    ";" 'evil-ex
    ":" 'evil-repeat-find-char)

  (general-def
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
    "/" '(swiper :wk "search")
    "rl" '(ivy-resume :wk "last")
    "sf" '(swiper :wk "file"))

  :config
  ;; set bindings if minibuffer uses evil or not
  (general-def ivy-minibuffer-map
    "C-j" 'ivy-next-line
    "C-k" 'ivy-previous-line)

  (add-to-list 'ivy-ignore-buffers #'my--ignore-dired-buffers)

  (ivy-mode 1))

;; ivy specific versions of emacs commands
(use-package counsel
  ;; :ensure t
  :config
  (counsel-mode 1))

;; code completion
(use-package company
  ;; :ensure t
  :hook
  (prog-mode . company-mode))

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

;; with company
(use-package company-prescient
  ;; :ensure t
  :after company prescient
  :config
  (company-prescient-mode 1))

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
  (projectile-mode +1)
  (setq projectile-enable-caching t))

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
  (prog-mode . flycheck-mode))

;; git ui
(use-package magit
  ;; :ensure t
  :general
  (my:leader "gs" '(magit-status :wk "status")))

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
 tab-width 2)

(use-package editorconfig
  ;; :ensure t
  :defer 1
  :config
  (editorconfig-mode 1))

(use-package lsp-mode
  ;; :ensure t
  :config
  (lsp-define-stdio-client
   lsp-javascript-typescript
   "javascript"
   #'projectile-project-root
   ;; '("typescript-language-server" "--stdio"))
   '("javascript-typescript-stdio"))
  :hook
  (lsp-after-open . lsp-enable-imenu)
  (js2-mode . lsp-javascript-typescript-enable))

(use-package lsp-ui
  ;; :ensure t
  :init
  (setq lsp-ui-flycheck-enable nil)
  ;; (setq lsp-ui-sideline-show-code-actions nil)
  :hook
  (lsp-mode . lsp-ui-mode))

(use-package company-lsp
  ;; :ensure t
  :after company lsp-mode
  :config
  (push 'company-lsp company-backends))

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
  (js2-mode . js2-refactor-mode))

(use-package json-mode
  ;; :ensure t
  :mode "\\.json\\'")

(use-package web-mode
  ;; :ensure t
  :mode "\\.jsx\\'"
  :mode "\\.hbs\\'"
  :init
  (setq
   web-mode-comment-style 2
   web-mode-enable-current-element-highlight t)
  (add-hook 'editorconfig-after-apply-functions
            (lambda (hash)
              (let* ((indent_size (gethash 'indent_size hash "2"))
                     (indent (string-to-number indent_size)))
                (setq web-mode-block-padding (- indent 2))))))

(use-package add-node-modules-path
  ;; :ensure t
  :hook
  (js2-mode . add-node-modules-path)
  (json-mode . add-node-modules-path)
  (web-mode . add-node-modules-path))

;; formatting
(use-package format-all
  ;; :ensure t
  :hook
  (emacs-lisp-mode . format-all-mode)
  (lisp-interaction-mode . format-all-mode)
  (js2-mode . format-all-mode)
  (json-mode . format-all-mode)
  :config
  (my:leader
    "bf" '(format-all-buffer :wk "format")))

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
