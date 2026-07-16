# frozen_string_literal: true

require "rails_helper"

RSpec.describe PanelsUI::Switch, type: :component do
  SwitchObject = Class.new do
    include ActiveModel::Model
    attr_accessor :notifications
  end

  def form_for(object = SwitchObject.new)
    ActionView::Helpers::FormBuilder.new(:profile, object, vc_test_view_context, {})
  end

  it "renders a builder switch with role=switch and Rails unchecked-value support" do
    render_inline(
      described_class.new(
        form: form_for, attribute: :notifications, label: "Email notifications",
        description: "We will email booking updates.", checked: true
      )
    )

    expect(page).to have_css("label.panel-switch[for='profile_notifications'][data-size='md'][data-variant='default']", text: "Email notifications")
    expect(page).to have_css("input[type='hidden'][name='profile[notifications]'][value='0']", visible: :all)
    expect(page).to have_css("input#profile_notifications.panel-switch__input[type='checkbox'][role='switch'][value='1'][checked]")
    expect(page).to have_css("#profile_notifications-description.panel-switch__description", text: "We will email booking updates.")
  end

  it "derives an error from the builder object and replaces the description" do
    object = SwitchObject.new
    object.errors.add(:notifications, "must be enabled")

    render_inline(described_class.new(form: form_for(object), attribute: :notifications, label: "Notifications", description: "Toggle me."))

    expect(page).to have_css("input[role='switch'][aria-invalid='true'][aria-describedby='profile_notifications-error']")
    expect(page).to have_css("#profile_notifications-error.panel-switch__error[role='alert']", text: "must be enabled")
    expect(page).to have_no_css("#profile_notifications-description")
  end

  it "renders a standalone card switch with custom attributes" do
    render_inline(
      described_class.new(
        name: "beta", value: "on", checked: true, label: "Beta features",
        variant: :card, size: :lg, disabled: true, class: "w-full"
      )
    )

    expect(page).to have_css("label.panel-switch[data-variant='card'][data-size='lg'][data-disabled='true']")
    expect(page).to have_css("input.panel-switch__input.w-full[type='checkbox'][role='switch'][name='beta'][value='on'][checked][disabled]")
  end

  it "rejects missing labels and invalid control sources" do
    expect { described_class.new(name: "beta", label: nil) }.to raise_error(ArgumentError, "Switches require a label")
    expect { described_class.new(form: form_for, label: "Beta") }.to raise_error(ArgumentError, "Switches require either form: and attribute:, or name:")
  end
end
