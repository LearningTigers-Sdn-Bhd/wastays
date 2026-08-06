# frozen_string_literal: true

require "rails_helper"

RSpec.describe PanelsUI::Toggle, type: :component do
  ToggleObject = Struct.new(:focus_mode)

  def form_for(object)
    ActionView::Helpers::FormBuilder.new(:preferences, object, vc_test_view_context, {})
  end

  def render_toggle(**options, &block)
    render_inline(described_class.new(**options), &block)
  end

  it "renders an unpressed button with stable state semantics" do
    render_toggle { "Show rates" }

    expect(page).to have_css(".panel-toggle-root[data-slot='toggle-root'][data-controller='panels-ui--toggle']")
    expect(page).to have_button("Show rates")
    expect(page).to have_css(
      "button.panel-toggle[data-slot='toggle'][data-state='off'][data-variant='default'][data-size='md']" \
      "[aria-pressed='false'][type='button']"
    )
    expect(page).to have_no_css("input[type='hidden']", visible: :all)
  end

  it "renders pressed, disabled, variant, size, and passthrough attributes" do
    render_toggle(
      pressed: true,
      disabled: true,
      variant: :outline,
      size: :sm,
      id: "rates-toggle",
      class: "w-full",
      data: { controller: "probe", action: "click->probe#record" },
      aria: { describedby: "rates-help" }
    ) { "Rates" }

    button = page.find("#rates-toggle")
    expect(button["aria-pressed"]).to eq("true")
    expect(button["aria-describedby"]).to eq("rates-help")
    expect(button["data-state"]).to eq("on")
    expect(button["data-variant"]).to eq("outline")
    expect(button["data-size"]).to eq("sm")
    expect(button["data-controller"]).to eq("probe")
    expect(button["data-action"]).to include("click->panels-ui--toggle#toggle", "click->probe#record")
    expect(button[:class]).to include("w-full")
    expect(button).to be_disabled
  end

  it "mirrors a name-backed state into one hidden field" do
    render_toggle(name: "filters[rates]", pressed: true, value: "yes", unchecked_value: "no") { "Rates" }

    input = page.find("input[type='hidden'][name='filters[rates]']", visible: :all)
    expect(input.value).to eq("yes")
    expect(input["data-pressed-value"]).to eq("yes")
    expect(input["data-unpressed-value"]).to eq("no")
    expect(input["data-panels-ui--toggle-target"]).to eq("input")
  end

  it "derives a builder-backed initial state and field name from the object" do
    render_toggle(form: form_for(ToggleObject.new("1")), attribute: :focus_mode) { "Focus mode" }

    expect(page).to have_css("button[aria-pressed='true'][data-state='on']", text: "Focus mode")
    expect(page).to have_css("input[type='hidden'][name='preferences[focus_mode]'][value='1']", visible: :all)
  end

  it "supports every Panels UI button size and infers icon-only sizing" do
    described_class::SIZES.each do |size|
      options = { size: }
      options[:aria_label] = size.to_s if described_class::ICON_SIZES.include?(size)
      render_toggle(**options) { size.to_s }
      button = page.find("button", text: size.to_s)
      expect(button["data-size"]).to eq(size.to_s)
      expect(button["data-icon-only"]).to eq("true") if described_class::ICON_SIZES.include?(size)
    end
  end

  it "rejects inaccessible icon-only toggles" do
    expect { render_toggle(size: :icon) { "icon" } }.to raise_error(
      ArgumentError,
      "Icon-only toggles require an aria_label or aria: { label: ... }"
    )
  end

  it "rejects unsupported options and conflicting form sources" do
    expect { described_class.new(variant: :solid) }.to raise_error(ArgumentError, /variant/)
    expect { described_class.new(size: :huge) }.to raise_error(ArgumentError, /size/)
    expect { described_class.new(form: form_for(ToggleObject.new), attribute: :focus_mode, name: "focus") }
      .to raise_error(ArgumentError, /form: and attribute:/)
    expect { described_class.new(form: form_for(ToggleObject.new)) }.to raise_error(ArgumentError, /form: and attribute:/)
    expect { described_class.new(name: "") }.to raise_error(ArgumentError, /form: and attribute:/)
  end
end
