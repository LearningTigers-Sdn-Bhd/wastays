# frozen_string_literal: true

require "rails_helper"

RSpec.describe GuestUI::TextArea, type: :component do
  GuestTextAreaObject = Class.new do
    include ActiveModel::Model
    attr_accessor :details
  end

  def render_area(**options)
    form = ActionView::Helpers::FormBuilder.new(:stay, GuestTextAreaObject.new, vc_test_view_context, {})
    render_inline(described_class.new(form: form, attribute: :details, **options))
  end

  it "takes its id from the form, so a label can point at it" do
    render_area

    expect(page).to have_css("textarea#stay_details.guest-text-area[name='stay[details]'][rows='4']")
  end

  # rows says where it starts, not where it stops: the stylesheet grows it with
  # what is written, so a guest who types four lines can read all four.
  it "starts at the height the caller asked for" do
    render_area(rows: 6)

    expect(page).to have_css("textarea[rows='6']")
  end

  it "reports that it is invalid and says where the reason is" do
    render_area(invalid: true, described_by: "stay_details-error")

    expect(page).to have_css(".guest-text-area[aria-invalid='true'][aria-describedby='stay_details-error']")
  end

  it "carries required, disabled, and readonly" do
    render_area(required: true, disabled: true, readonly: true)

    expect(page).to have_css("textarea[required][disabled][readonly]")
  end
end
