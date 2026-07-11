require_relative "../color_contrast"

namespace :tokens do
  desc "Audit public/panel theme tokens for WCAG 2.2 AA contrast"
  task :contrast do
    public_vars = TokenAudit.parse_block("app/assets/tailwind/public/theme.css", /:root\s*\{/)
    panel_light_vars = TokenAudit.parse_block("app/assets/tailwind/panel/theme.css", /\[data-theme=['"]?panel-light['"]?\]\s*\{/)
    panel_dark_vars  = TokenAudit.parse_block("app/assets/tailwind/panel/theme.css", /\[data-theme=['"]?panel-dark['"]?\]\s*\{/)

    failures = []
    [ [ "public", public_vars ], [ "panel-light", panel_light_vars ], [ "panel-dark", panel_dark_vars ] ].each do |theme_name, vars|
      TokenAudit::PAIRS.each do |fg, bg, min_ratio, label|
        next unless vars[fg] && vars[bg]

        ratio = ColorContrast.contrast(vars[fg], vars[bg])
        status = ratio >= min_ratio ? "PASS" : "FAIL"
        printf("%-7s %-28s %5.2f:1  (need %.1f:1)  [%s]\n", status, "#{theme_name}: #{label}", ratio, min_ratio, "--#{fg} on --#{bg}")
        failures << "#{theme_name}: #{label} (--#{fg} on --#{bg}) = #{ratio.round(2)}:1, needs #{min_ratio}:1" if status == "FAIL"
      end
    end

    if failures.any?
      warn "\n#{failures.size} contrast failure(s):"
      failures.each { |f| warn "  - #{f}" }
      abort "tokens:contrast failed"
    else
      puts "\nAll token pairs meet WCAG 2.2 AA."
    end
  end
end

module TokenAudit
  # [foreground_var, surface_var, minimum_ratio, label]
  PAIRS = [
    [ "foreground", "background", 4.5, "foreground/background" ],
    [ "foreground", "card", 4.5, "foreground/card" ],
    [ "card-foreground", "card", 4.5, "card-foreground/card" ],
    [ "muted-foreground", "background", 4.5, "muted-foreground/background" ],
    [ "muted-foreground", "muted", 4.5, "muted-foreground/muted" ],
    [ "muted-foreground", "card", 4.5, "muted-foreground/card" ],
    [ "primary-foreground", "primary", 4.5, "primary-foreground/primary" ],
    [ "secondary-foreground", "secondary", 4.5, "secondary-foreground/secondary" ],
    [ "accent-foreground", "accent", 4.5, "accent-foreground/accent" ],
    [ "destructive-foreground", "destructive", 4.5, "destructive-foreground/destructive" ],
    [ "warning-foreground", "warning", 4.5, "warning-foreground/warning" ],
    [ "success-foreground", "success", 4.5, "success-foreground/success" ],
    [ "info-foreground", "info", 4.5, "info-foreground/info" ],
    [ "border-interactive", "background", 3.0, "border-interactive/background" ],
    [ "border-interactive", "card", 3.0, "border-interactive/card" ],
    [ "ring", "background", 3.0, "ring/background" ],
    [ "ring", "card", 3.0, "ring/card" ],
    [ "sidebar-foreground", "sidebar", 4.5, "sidebar foreground" ],
    [ "sidebar-muted-foreground", "sidebar", 4.5, "sidebar muted foreground" ],
    [ "sidebar-accent-foreground", "sidebar-accent", 4.5, "sidebar accent foreground" ],
    [ "sidebar-tooltip-foreground", "sidebar-tooltip", 7.0, "sidebar tooltip foreground" ],
    [ "sidebar-popup-foreground", "sidebar-popup", 7.0, "sidebar popup foreground" ],
    [ "sidebar-popup-muted-foreground", "sidebar-popup", 4.5, "sidebar popup muted foreground" ],
    [ "sidebar-popup-accent-foreground", "sidebar-popup-accent", 4.5, "sidebar popup accent foreground" ],
    [ "sidebar-popup-border", "sidebar-popup", 3.0, "sidebar popup boundary" ],
    [ "sidebar-ring", "sidebar", 3.0, "sidebar focus ring" ]
  ].freeze

  def self.parse_block(path, selector_regex)
    css = File.read(path)
    start = css.index(selector_regex)
    raise "selector #{selector_regex.inspect} not found in #{path}" unless start

    open_brace = css.index("{", start)
    close_brace = css.index("}", open_brace)
    block = css[(open_brace + 1)...close_brace]

    vars = {}
    block.scan(/--([\w-]+)\s*:\s*([^;]+);/) do |name, value|
      vars[name] = value.strip
    end
    vars
  end
end
