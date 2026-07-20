# frozen_string_literal: true

require "rails_helper"

RSpec.describe PanelsUI::ToggleGroup, type: :component do
  ToggleGroupObject = Struct.new(:density, :formatting)

  def form_for(object)
    ActionView::Helpers::FormBuilder.new(:preferences, object, vc_test_view_context, {})
  end

  def render_group(**options)
    defaults = { id: "example-group", aria_label: "Example choices" }
    render_inline(described_class.new(**defaults.merge(options))) do |group|
      yield group
    end
  end

  it "renders a labelled single group with inherited item styling and roving tabindex" do
    render_group(value: "comfortable", variant: :outline, size: :sm, spacing: 0, required: true) do |group|
      group.with_item(value: "compact") { "Compact" }
      group.with_item(value: "comfortable") { "Comfortable" }
      group.with_item(value: "spacious", disabled: true) { "Spacious" }
    end

    root = page.find("#example-group")
    expect(root[:role]).to eq("group")
    expect(root["aria-label"]).to eq("Example choices")
    expect(root["aria-orientation"]).to eq("horizontal")
    expect(root["aria-required"]).to eq("true")
    expect(root["data-controller"]).to eq("panels-ui--toggle-group")
    expect(root["data-type"]).to eq("single")
    expect(root["data-variant"]).to eq("outline")
    expect(root["data-size"]).to eq("sm")
    expect(root["data-spacing"]).to eq("0")

    expect(page).to have_css("button[data-value='compact'][aria-pressed='false'][data-state='off'][tabindex='-1']")
    expect(page).to have_css(
      "button.panel-toggle-group__item[data-value='comfortable'][aria-pressed='true'][data-state='on']" \
      "[data-variant='outline'][data-size='sm'][tabindex='0']"
    )
    expect(page).to have_button("Spacious", disabled: true)
  end

  it "renders Rails-compatible single and multiple hidden values" do
    render_group(type: :single, name: "display[density]", value: "compact") do |group|
      group.with_item(value: "compact") { "Compact" }
      group.with_item(value: "comfortable") { "Comfortable" }
    end
    expect(page).to have_css("input[type='hidden'][name='display[density]'][value='compact']", visible: :all)

    render_group(id: "formatting", type: :multiple, name: "editor[formatting]", value: %w[bold underline]) do |group|
      group.with_item(value: "bold") { "Bold" }
      group.with_item(value: "italic") { "Italic" }
      group.with_item(value: "underline") { "Underline" }
    end

    expect(page).to have_css("input[type='hidden'][name='editor[formatting][]'][value='']", visible: :all)
    expect(page).to have_css("input[type='hidden'][name='editor[formatting][]']:not([disabled])", count: 3, visible: :all)
    expect(page).to have_css("input[type='hidden'][name='editor[formatting][]'][value='italic'][disabled]", visible: :all)
  end

  it "derives builder-backed single and multiple values" do
    object = ToggleGroupObject.new("comfortable", %w[bold italic])

    render_group(form: form_for(object), attribute: :density) do |group|
      group.with_item(value: "compact") { "Compact" }
      group.with_item(value: "comfortable") { "Comfortable" }
    end
    expect(page).to have_css("input[name='preferences[density]'][value='comfortable']", visible: :all)

    render_group(id: "builder-multiple", type: :multiple, form: form_for(object), attribute: :formatting) do |group|
      group.with_item(value: "bold") { "Bold" }
      group.with_item(value: "italic") { "Italic" }
    end
    expect(page).to have_css("input[name='preferences[formatting][]'][value='bold']:not([disabled])", visible: :all)
    expect(page).to have_css("input[name='preferences[formatting][]'][value='italic']:not([disabled])", visible: :all)
  end

  it "supports vertical orientation, passthrough attributes, and item actions" do
    render_group(
      orientation: :vertical,
      disabled: true,
      class: "w-full",
      data: { controller: "probe" },
      aria: { describedby: "group-help" }
    ) do |group|
      group.with_item(value: "one", data: { action: "click->probe#record" }, class: "custom-item") { "One" }
    end

    root = page.find("#example-group")
    expect(root["aria-orientation"]).to eq("vertical")
    expect(root["aria-disabled"]).to eq("true")
    expect(root["aria-describedby"]).to eq("group-help")
    expect(root["data-controller"]).to include("probe", "panels-ui--toggle-group")
    expect(root[:class]).to include("w-full")
    item = page.find("button", text: "One")
    expect(item[:class]).to include("custom-item")
    expect(item["data-action"]).to include("click->panels-ui--toggle-group#toggle", "click->probe#record")
    expect(item).to be_disabled
  end

  it "requires accessible names for icon-sized items" do
    expect {
      render_group(size: :icon) { |group| group.with_item(value: "pin") { "icon" } }
    }.to raise_error(ArgumentError, /Icon-only toggle group items/)

    render_group(size: :icon) do |group|
      group.with_item(value: "pin", aria_label: "Pin toolbar") { "icon" }
    end
    expect(page).to have_css("button[aria-label='Pin toolbar'][data-icon-only='true']")
  end

  invalid_cases = {
    "a label" => { options: { aria_label: nil }, items: [ [ "one", "One" ] ] },
    "items" => { options: {}, items: [] },
    "nonblank values" => { options: {}, items: [ [ "", "Blank" ] ] },
    "unique values" => { options: {}, items: [ [ "one", "One" ], [ "one", "Duplicate" ] ] },
    "matching selected values" => { options: { value: "missing" }, items: [ [ "one", "One" ] ] }
  }

  invalid_cases.each do |description, config|
    it "requires #{description}" do
      expect {
        render_group(**config[:options]) do |group|
          config[:items].each { |value, label| group.with_item(value:) { label } }
        end
      }.to raise_error(ArgumentError)
    end
  end

  it "rejects invalid group options, array values for single groups, and conflicting sources" do
    expect { described_class.new(type: :exclusive, aria_label: "Choices") }.to raise_error(ArgumentError, /type/)
    expect { described_class.new(variant: :solid, aria_label: "Choices") }.to raise_error(ArgumentError, /variant/)
    expect { described_class.new(size: :huge, aria_label: "Choices") }.to raise_error(ArgumentError, /size/)
    expect { described_class.new(orientation: :diagonal, aria_label: "Choices") }.to raise_error(ArgumentError, /orientation/)
    expect { described_class.new(spacing: 3, aria_label: "Choices") }.to raise_error(ArgumentError, /spacing/)
    expect { described_class.new(form: form_for(ToggleGroupObject.new), attribute: :density, name: "density", aria_label: "Choices") }
      .to raise_error(ArgumentError, /form: and attribute:/)
    expect { described_class.new(name: "", aria_label: "Choices") }.to raise_error(ArgumentError, /form: and attribute:/)

    expect {
      render_group(value: %w[one]) { |group| group.with_item(value: "one") { "One" } }
    }.to raise_error(ArgumentError, /scalar/)
  end
end
