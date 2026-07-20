# frozen_string_literal: true

# Helpers for interacting with controls inside a native modal <dialog> (PanelsUI
# Sheet / Dialog opened via showModal()).
#
# Such dialogs render in the browser's top layer. cuprite drives clicks by
# computing an element's coordinates and dispatching a synthetic mouse event, and
# its hit-testing intermittently fails to resolve elements in the top layer — so a
# normal `click_link` / `click_button` reports success yet the click never lands,
# and the flow silently stalls. Dispatching the DOM click event directly on the
# element (Ferrum's `trigger("click")`) bypasses hit-testing and always fires, so
# the event bubbles to Turbo / Stimulus exactly as a real user click would.
#
# Use these ONLY for controls inside an open modal <dialog>. Elsewhere prefer the
# standard Capybara actions, which also verify the element is actually clickable.
module OverlayInteractionHelper
  # Click a control inside an open modal dialog.
  #
  #   click_in_overlay "Print / Send"                    # link/button by text
  #   click_in_overlay find("summary", text: "Changes")  # any pre-found node
  def click_in_overlay(locator_or_node = nil, selector: :link_or_button, **options)
    node = locator_or_node.is_a?(Capybara::Node::Element) ? locator_or_node : find(selector, locator_or_node, **options)
    # A real click focuses the element before firing; trigger("click") does not.
    # Focus first so focus-dependent behaviour (e.g. a dialog recording the
    # invoker for focus restoration on close) matches a genuine user click.
    page.execute_script("arguments[0].focus()", node)
    node.trigger("click")
    node
  end
end

RSpec.configure do |config|
  config.include OverlayInteractionHelper, type: :system
end
