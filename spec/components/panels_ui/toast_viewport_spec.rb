# frozen_string_literal: true

require "rails_helper"

RSpec.describe PanelsUI::ToastViewport, type: :component do
  it "renders a RailsBlocks-compatible host at the given placement" do
    render_inline(described_class.new(id: "toast-viewport", placement: :top_left))

    expect(page).to have_css(
      "#toast-viewport[role='region'][aria-label='Notifications'][data-controller='toast']" \
      "[data-toast-position-value='top-left'][data-toast-layout-value='default']" \
      "[data-toast-auto-dismiss-duration-value='4000'][data-toast-limit-value='3'][data-toast-gap-value='14']"
    )
    expect(page).to have_css("#toast-viewport [data-toast-target='container'][data-position='top-left']")
    expect(page).to have_css("#toast-viewport template[data-toast-icon-template='success']", visible: :all)
    expect(page).to have_css("#toast-viewport template[data-toast-icon-template='error']", visible: :all)
  end

  it "defaults to top_right and falls back to it for an unknown placement" do
    render_inline(described_class.new(id: "toast-viewport", placement: :unknown))

    expect(page).to have_css("[data-toast-position-value='top-right']")
  end
end
