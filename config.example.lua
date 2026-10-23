-- Copy to ~/.hammerspoon/safari-arc-kit-config.lua and edit. Every key is optional.
return {
  -- ⌃<key> raises the Safari window of that profile (window title prefix "<name> — ").
  profiles = {
    {key = "1", name = "Personal"},
    {key = "2", name = "Work"},
  },

  -- Icons at the top of the hover sidebar, per profile name.
  favorites = {
    Personal = {
      {title = "Gmail", url = "https://mail.google.com/mail/u/0/#inbox"},
      {title = "GitHub", url = "https://github.com/"},
    },
    Work = {
      {title = "Jira", url = "https://example.atlassian.net/jira/projects"},
    },
  },

  -- ⌘T prefix modes: "gh foo" opens url with %s replaced by the percent-encoded query.
  modes = {
    gh = {label = "GitHub my-org", url = "https://github.com/my-org?q=%s"},
    jira = {label = "Jira JQL", url = "https://example.atlassian.net/issues/?jql=%s"},
  },

  -- Tabs whose URL matches a Lua pattern are closed `delay` seconds after they become active.
  autoclose = {
    {name = "oauth callback", pattern = "^https?://127%.0%.0%.1:%d+/oauth/callback%?.*code=", delay = 0.5},
    {name = "oauth callback", pattern = "^https?://localhost:%d+/oauth/callback%?.*code=", delay = 0.5},
    {name = "aws vpn client", pattern = "^http://127%.0%.0%.1:35001/", delay = 2.0},
  },

  tabs = {maxEntries = 5, overlayDelay = 0.15},
  sidebar = {width = 280, stripWidth = 6, showDelay = 0.12},
  command = {width = 760, top = 0.3},
}
