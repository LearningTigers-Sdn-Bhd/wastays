# frozen_string_literal: true

require "rails_helper"

# A portal whose `body` is `overflow: hidden` gives up the document scroll, so
# its outermost box must be exactly one screenful: anything it pushes past the
# fold cannot be scrolled back. On a phone `100vh` is the *large* viewport --
# the height the page would have with the browser's address bar hidden -- and
# these portals never scroll, so that bar never hides. A `100vh` shell is
# therefore a screenful plus the chrome, and whatever sits on its bottom edge
# (the booking workspace's Save and View GRC buttons, for one) lands underneath
# the chrome, unreachable.
#
# This cost a real bug that no system spec could see: headless Chrome has no
# address bar, so `100vh`, `100dvh` and `window.innerHeight` all agree there and
# the shell measures correctly however short the window is made.
RSpec.describe "Portal shell viewport sizing" do
  # The portals that trade the document scroll for their own scroll regions.
  SCROLL_LOCKED_LAYOUTS = %w[
    app/views/layouts/_hotel_shell.html.erb
    app/views/layouts/corporate.html.erb
    app/views/layouts/onboarding.html.erb
  ].freeze

  SCROLL_LOCKED_LAYOUTS.each do |layout|
    context layout do
      let(:markup) { Rails.root.join(layout).read }

      it "locks the document scroll, which is what makes the shell's height load-bearing" do
        expect(markup).to match(/<body[^>]*\boverflow-hidden\b/)
      end

      it "sizes its shell with panel-shell rather than viewport-height utilities" do
        expect(markup).to include("panel-shell")

        # `h-screen`/`min-h-screen` are not merely redundant beside `h-dvh`:
        # Tailwind emits the `vh` utilities *after* the `dvh` ones no matter
        # how the class attribute orders them, so adding one silently wins.
        expect(markup).not_to match(/\b(?:min-)?h-screen\b/)
      end
    end
  end

  # The build is gitignored, so CI compiles it before the suite runs. A working
  # copy that has not run `bin/rails tailwindcss:build` has nothing to assert
  # against, which is a missing build rather than a regression.
  describe "the compiled panel-shell rule", :aggregate_failures do
    let(:build) { Rails.root.join("app/assets/builds/tailwind.css") }

    before { skip("Tailwind build not compiled in this working copy") unless build.exist? }

    it "resolves height and min-height to the dynamic viewport, never the large one" do
      rule = build.read[/\.panel-shell\s*\{[^}]*\}/]

      expect(rule).to be_present
      expect(rule).to include("100dvh")
      expect(rule).not_to include("100vh")
    end
  end
end
