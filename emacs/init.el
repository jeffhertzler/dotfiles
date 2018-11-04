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

;; Install straight.el package manager
(setq straight-check-for-modifications 'live)
(defvar bootstrap-version)
(let
  (
    (bootstrap-file
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
  fill-column 120
  indent-tabs-mode nil
  inhibit-startup-message t
  initial-scratch-message nil
  ring-bell-function #'ignore
  sentence-end-double-space nil
  vc-follow-symlinks t
  visible-bell nil
  save-interprogram-paste-before-kill t
)

;; line numbers in prog and text mode
(add-hook 'prog-mode-hook
  (lambda () (setq display-line-numbers 'relative)))
(add-hook 'text-mode-hook
  (lambda () (setq display-line-numbers 'relative)))

;; mode lighters
(use-package blackout
  :straight (:host github :repo "raxod502/blackout")
  :config
  (blackout 'emacs-lisp-mode "elisp")
  (blackout 'lisp-interaction-mode "elisp")
  (blackout 'eldoc-mode))

;; Package `no-littering' changes the default paths for lots of
;; different packages, with the net result that the ~/.emacs.d folder
;; is much more clean and organized.
(use-package no-littering
  :config
  (setq
    auto-save-file-name-transforms
      `((".*" ,(no-littering-expand-var-file-name "auto-save/") t))
    custom-file
      (no-littering-expand-etc-file-name "custom.el")))

;; Package `git' is a library providing convenience functions for
;; running Git.
(use-package git :defer t)

;;; Prevent Emacs-provided Org from being loaded

;; The following is a temporary hack until straight.el supports
;; building Org, see:
;;
;; * https://github.com/raxod502/straight.el/issues/211
;; * https://github.com/raxod502/radian/issues/410
;;
;; There are three things missing from our version of Org: the
;; functions `org-git-version' and `org-release', and the feature
;; `org-version'. We provide all three of those ourself, therefore.

(defun org-git-version ()
  "The Git version of org-mode.
  Inserted by installing org-mode or when a release is made."
  (require 'git)
  (let ((git-repo (expand-file-name
                   "straight/repos/org/" user-emacs-directory)))
    (string-trim
     (git-run "describe"
              "--match=release\*"
              "--abbrev=6"
              "HEAD"))))

(defun org-release ()
  "The release version of org-mode.
  Inserted by installing org-mode or when a release is made."
  (require 'git)
  (let ((git-repo (expand-file-name
                   "straight/repos/org/" user-emacs-directory)))
    (string-trim
     (string-remove-prefix
      "release_"
      (git-run "describe"
               "--match=release\*"
               "--abbrev=0"
               "HEAD")))))

(provide 'org-version)

;; Our real configuration for Org comes much later. Doing this now
;; means that if any packages that are installed in the meantime
;; depend on Org, they will not accidentally cause the Emacs-provided
;; (outdated and duplicated) version of Org to be loaded before the
;; real one is registered.
(straight-use-package 'org)

;; key bindings package
(use-package general
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
    :prefix "SPC"
    :non-normal-prefix "C-SPC")

  ;; setup local leader definer
  (general-create-definer my:local-leader
    :states '(normal motion visual insert emacs)
    :prefix "SPC m"
    :non-normal-prefix "C-SPC m")

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

    "p" '(:ignore t :wk "project")

    "q" '(:ignore t :wk "quit")
    "qq" '(save-buffers-kill-emacs :wk "quit")
    "qQ" '(kill-emacs :wk "quit!")

    "t" '(:ignore t :wk "toggle")
    "tw" '(whitespace-mode :wk "whitespace")

    "w" '(:ignore t :wk "window")
    "wl" '(windmove-right :wk "right")
    "wh" '(windmove-left :wk "left")
    "wk" '(windmove-up :wk "up")
    "wj" '(windmove-down :wk "down"))

  (general-create-definer my:normal
    :states '(normal motion visual))

  (my:normal
    "-" 'dired-jump
    ";" 'evil-ex
    ":" 'evil-repeat-find-char)

  (general-def
    "s-P" 'execute-extended-command
    "s-p" 'find-file
    "s-<return>" 'toggle-frame-fullscreen))

(use-package exec-path-from-shell
  :config
  (exec-path-from-shell-initialize)
  (let ((gls (executable-find "gls")))
    (when gls
      (setq insert-directory-program gls
            dired-listing-switches "-aBhl --group-directories-first"))))

;; evil mode
(use-package evil
  :init
  ;; disable built in evil keybindings in favor of evil-collection
  (setq evil-want-keybinding nil)

  :config
  (evil-mode 1))

;; evil keybindings for other packages
(use-package evil-collection
  :after evil
  :config
  (evil-collection-init))

;; code commenting
(use-package evil-commentary
  :blackout
  :after evil
  :hook
  (prog-mode . evil-commentary-mode))

;; theme
(use-package doom-themes
  :config
  (load-theme 'doom-dracula t)
  (doom-themes-treemacs-config))

;; keybinding documentation
(use-package which-key
  :defer 1
  :blackout
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
  :defer 1
  :blackout
  :init
  (setq ivy-count-format "%d/%d ")

  :general
  (my:normal "/" '(swiper :wk "search"))
  (my:leader "/" '(swiper :wk "search"))

  :config
  ;; set bindings if minibuffer uses evil or not
  (general-def ivy-minibuffer-map
    "C-j" 'ivy-next-line
    "C-k" 'ivy-previous-line)

  (add-to-list 'ivy-ignore-buffers #'my--ignore-dired-buffers)

  (ivy-mode 1))

;; ivy specific versions of emacs commands
(use-package counsel
  :blackout
  :config
  (counsel-mode 1))

;; code completion
(use-package company
  :blackout
  :hook
  (prog-mode . company-mode))

;; sorting and filtering
(use-package prescient
  :init
  ;; options: '(literal+initialism literal initialism regexp fuzzy)
  (setq prescient-filter-method 'literal+initialism)
  :config
  (prescient-persist-mode 1))

;; with ivy
(use-package ivy-prescient
  :after ivy prescient
  :config
  (ivy-prescient-mode 1))

;; with company
(use-package company-prescient
  :after company prescient
  :config
  (company-prescient-mode 1))

(use-package ace-window
  :blackout "aw"
  :general
  (my:leader "ww" '(ace-window :wk "ace window")))

(use-package treemacs
  :general
  (my:leader "ft" '(treemacs :wk "tree")))

(use-package treemacs-evil
  :after treemacs evil)

(use-package treemacs-projectile
  :after treemacs projectile)

;; projects
(use-package projectile
  :blackout
  :general
  (my:leader "pb" '(projectile-switch-to-buffer :wk "buffer"))
  (my:leader "pf" '(projectile-find-file :wk "file"))
  (my:leader "pl" '(projectile-switch-project :wk "list"))
  (my:leader "ps" '(projectile-ripgrep :wk "search"))
  :config
  (projectile-mode +1)
  (setq projectile-enable-caching t))

;; projects via counsel
(use-package counsel-projectile
  :blackout
  :config
  (counsel-projectile-mode))

(use-package rainbow-delimiters
  :blackout
  :hook
  (prog-mode . rainbow-delimiters-mode))

;; better undo
(use-package undo-tree
  :blackout
  :config
  (global-undo-tree-mode +1))

(use-package subword
  :blackout "sw"
  :general
  (my:leader "ts" '(subword-mode :wk "subword mode"))
  :hook
  (prog-mode . subword-mode))

(use-package doom-modeline
  :config
  (setq doom-modeline-buffer-file-name-style 'truncate-upto-root)
  :hook (after-init . doom-modeline-init))

(use-package all-the-icons)

(use-package yasnippet
  :defer 1
  :init
  ;; don't give me init message
  (setq yas-verbosity 1)        
  :config
  (yas-global-mode)
  (blackout 'yas-minor-mode))

(use-package flycheck
  :blackout "flycheck"
  :hook
  (prog-mode . flycheck-mode))

;; git ui
(use-package magit
  :blackout
  :general
  (my:leader "gs" '(magit-status :wk "status")))

;; vim keybindings for magit
(use-package evil-magit
  :after evil magit)

;; emacs startup profiler
(use-package esup)

;; restart emacs
(use-package restart-emacs
  :general
  (my:leader "qr" '(restart-emacs :wk "restart emacs")))

;; indentation
(setq-default
  c-basic-offset 2
  css-indent-offset 2
  js-indent-level 2
  tab-width 2)

(use-package lsp-mode
  :blackout "lsp"
  :config
  (lsp-define-stdio-client
    lsp-javascript-typescript
    "javascript"
    #'projectile-project-root
    '("typescript-language-server" "--stdio"))
    ;; '("javascript-typescript-stdio"))
  :hook
  (lsp-after-open . lsp-enable-imenu)
  (js2-mode . lsp-javascript-typescript-enable))

(use-package lsp-ui
  :init
  (setq lsp-ui-flycheck-enable nil)
  (setq lsp-ui-sideline-show-code-actions nil)
  :hook
  (lsp-mode . lsp-ui-mode))

(use-package company-lsp
  :after company lsp-mode
  :config
  (push 'company-lsp company-backends))

;; js
(use-package js2-mode
  :blackout "js"
  :mode "\\.js\\'"
  :interpreter "node"
  :config
  (setq
    js2-mode-show-parse-errors nil
    js2-mode-show-strict-warnings nil))

(use-package json-mode
  :mode "\\.json\\'")

(use-package web-mode
  :mode "\\.jsx\\'"
  :mode "\\.hbs\\'")

(use-package add-node-modules-path
  :hook
  (js2-mode . add-node-modules-path)
  (json-mode . add-node-modules-path)
  (web-mode . add-node-modules-path))

;; formatting
(use-package prettier-js
  :blackout "prettier"
  :hook
  (js2-mode . prettier-js-mode)
  (json-mode . prettier-js-mode))

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
