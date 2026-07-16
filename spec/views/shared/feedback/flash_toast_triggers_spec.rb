# frozen_string_literal: true

require "rails_helper"

RSpec.describe "shared/feedback/_flash_toast_triggers", type: :view do
  it "renders a no-script status fallback with escaped content" do
    flash = ActionDispatch::Flash::FlashHash.new
    flash[:toast] = { message: "Saved <safely>", description: "Guest checked in", type: "success" }

    render partial: "shared/feedback/flash_toast_triggers", locals: { flash: flash }

    expect(rendered).to include("<noscript>", 'role="status"', "Saved &lt;safely&gt;", "Guest checked in")
  end

  it "uses an alert fallback for errors" do
    flash = ActionDispatch::Flash::FlashHash.new
    flash[:alert] = "Unable to save"

    render partial: "shared/feedback/flash_toast_triggers", locals: { flash: flash }

    expect(rendered).to include('role="alert"', "Unable to save")
  end
end
