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

;; make use-package is lazy by default
(setq use-package-always-defer t)

;; ensure we can install from git sources
(use-package git :demand)

;; The following package dependencies are used throughout the rest of the configuration.
;; They provide contemporary APIs for working with various elisp data structures.
(use-package dash :demand) ;; lists
(use-package ht :demand)   ;; hash-tables
(use-package s :demand)    ;; strings
(use-package a :demand)    ;; association lists

;; Minimal UI
(blink-cursor-mode -1)
(menu-bar-mode -1)
(scroll-bar-mode -1)
(tool-bar-mode -1)
(tooltip-mode -1)

;; MacOS tweaks
(add-to-list 'default-frame-alist '(ns-transparent-titlebar . t))
(add-to-list 'default-frame-alist '(ns-appearance . dark))
(setq
  frame-title-format nil
  ns-use-proxy-icon  nil
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

(setq-default
  display-line-numbers 'relative
  fill-column 120
  indent-tabs-mode nil
  inhibit-startup-message t
  initial-scratch-message nil
  ring-bell-function #'ignore
  sentence-end-double-space nil
  vc-follow-symlinks t
  visible-bell nil
)

;; set font
(set-face-attribute 'default nil :family "Operator Mono Ssm Lig")

;; Package `no-littering' changes the default paths for lots of
;; different packages, with the net result that the ~/.emacs.d folder
;; is much more clean and organized.
(use-package no-littering
  :demand
  :config
    (setq
      auto-save-file-name-transforms
        `((".*" ,(no-littering-expand-var-file-name "auto-save/") t))
      custom-file
        (no-littering-expand-etc-file-name "custom.el")))

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
  :demand
  :config
    (general-evil-setup)
    (general-imap "f"
      (general-key-dispatch 'self-insert-command
        :timeout 0.25
        "d" 'evil-normal-state))
    (general-create-definer my-leader-def
      :prefix "SPC")
    (general-create-definer my-local-leader-def
      :prefix "SPC m")
    (my-leader-def
      :keymaps 'normal
      "SPC" 'execute-extended-command)
    (general-define-key
      "s-<return>" 'toggle-frame-fullscreen))

;; evil mode
(use-package evil
  :demand
  :init
    (setq evil-want-keybinding nil)
  :config
    (evil-mode 1))

;; evil keybindings for other packages
(use-package evil-collection
  :demand
  :after evil
  :config
    (evil-collection-init))

;; theme
(use-package dracula-theme
  :demand
  :config
    (load-theme 'dracula t))

;; Which Key
(use-package which-key
  :demand
  :init
    (setq which-key-separator " ")
    (setq which-key-prefix-prefix "+")
  :config
    (which-key-mode))

;; completion engine
(use-package helm
  :demand
  :init
    (setq helm-mode-fuzzy-match t)
    (setq helm-completion-in-region-fuzzy-match t)
    (setq helm-candidate-number-list 50))

;; projects
(use-package projectile
  :demand
  :config
    (setq projectile-enable-caching t)
    (projectile-mode t))

;; git ui
(use-package magit :demand)

(server-start)

;; reset
(defun my|finalize ()
  "Reset `gc-cons-threshold', `gc-cons-percentage' and `file-name-handler-alist'."
  (unless (or (not after-init-time) noninteractive)
    ;; If you forget to reset this, you'll get stuttering and random freezes!
    (setq
      gc-cons-threshold 16777216
      gc-cons-percentage 0.1
      file-name-handler-alist my--file-name-handler-alist))

  (message "Emacs ready in %s with %d garbage collections."
    (format "%.2f seconds"
      (float-time
        (time-subtract after-init-time before-init-time)))
  gcs-done))

(add-hook 'emacs-startup-hook #'my|finalize)