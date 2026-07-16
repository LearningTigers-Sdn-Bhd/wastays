# frozen_string_literal: true

require "rails_helper"

RSpec.describe PanelsUI::Checkbox, type: :component do
  CheckboxObject = Class.new do
    include ActiveModel::Model
    attr_accessor :accepted, :alerts
  end

  def form_for(object = CheckboxObject.new)
    ActionView::Helpers::FormBuilder.new(:profile, object, vc_test_view_context, {})
  end

  it "renders a builder checkbox with Rails unchecked-value support and an accessible description" do
    render_inline(
      described_class.new(
        form: form_for,
        attribute: :accepted,
        label: "Accept booking terms",
        description: "Required before confirmation.",
        required: true,
        checked: true,
        value: "yes",
        unchecked_value: "no",
        data: { controller: "booking-check" },
        aria: { describedby: "external-help" }
      )
    )

    expect(page).to have_css("label.panel-checkbox[for='profile_accepted'][data-size='md'][data-variant='default']", text: "Accept booking terms")
    expect(page).to have_css("input[type='hidden'][name='profile[accepted]'][value='no']", visible: :all)
    expect(page).to have_css("input#profile_accepted[type='checkbox'][name='profile[accepted]'][value='yes'][checked][required][data-controller='booking-check']")
    expect(page).to have_css("input[aria-describedby='external-help profile_accepted-description']")
    expect(page).to have_css("#profile_accepted-description.panel-checkbox__description", text: "Required before confirmation.")
    expect(page).to have_css(".panel-checkbox__label .panel-checkbox__required", text: "*", visible: :all)
    expect(page).to have_css(".panel-checkbox__label span.sr-only", text: "(required)", visible: :all)
    expect(page).to have_no_css("input[role], input[aria-checked]")
  end

  it "derives an error from the builder object and replaces the description" do
    object = CheckboxObject.new
    object.errors.add(:accepted, "must be accepted")

    render_inline(described_class.new(form: form_for(object), attribute: :accepted, label: "Accept terms", description: "Terms apply."))

    expect(page).to have_css("input[aria-invalid='true'][aria-describedby='profile_accepted-error']")
    expect(page).to have_css("#profile_accepted-error.panel-checkbox__error[role='alert']", text: "must be accepted")
    expect(page).to have_no_css("#profile_accepted-description")
  end

  it "renders standalone card checkboxes, custom ids, and caller attributes" do
    render_inline(
      described_class.new(
        name: "folio_ids[]",
        value: "42",
        checked: true,
        id: "folio-42",
        label: "Folio 42",
        description: "Open balance: MYR 120.00",
        variant: :card,
        size: :lg,
        class: "w-full",
        disabled: true
      )
    )

    expect(page).to have_css("label.panel-checkbox[data-variant='card'][data-size='lg'][data-disabled='true'][for='folio-42']")
    expect(page).to have_css("input#folio-42.panel-checkbox__input.w-full[type='checkbox'][name='folio_ids[]'][value='42'][checked][disabled]")
    expect(page).to have_css("#folio-42-description", text: "Open balance: MYR 120.00")
    expect(page).to have_no_css("input[type='hidden'][name='folio_ids[]']", visible: :all)
  end

  it "wires indeterminate checkboxes to the scoped controller without replacing native semantics" do
    render_inline(described_class.new(name: "select_all", label: "Select all", indeterminate: true))

    expect(page).to have_css("input[type='checkbox'][data-controller='panels-ui--checkbox'][data-action='change->panels-ui--checkbox#clearIndeterminate'][data-panels-ui--checkbox-indeterminate-value='true']")
    expect(page).to have_css("input[data-panels-ui--checkbox-target='input']")
  end

  it "falls back unknown sizes and variants to the defaults" do
    render_inline(described_class.new(name: "archive", label: "Archive", size: :huge, variant: :pill))

    expect(page).to have_css("label.panel-checkbox[data-size='md'][data-variant='default']")
  end

  it "rejects missing labels and invalid control sources" do
    expect { described_class.new(name: "archive", label: nil) }.to raise_error(ArgumentError, "Checkboxes require a label")
    expect { described_class.new(form: form_for, label: "Archive") }.to raise_error(ArgumentError, "Checkboxes require either form: and attribute:, or name:")
    expect { described_class.new(form: form_for, attribute: :accepted, name: "archive", label: "Archive") }.to raise_error(ArgumentError, "Checkboxes require either form: and attribute:, or name:")
  end
end
