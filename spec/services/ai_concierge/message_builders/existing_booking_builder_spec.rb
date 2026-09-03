# frozen_string_literal: true

require "rails_helper"

RSpec.describe AiConcierge::MessageBuilders::ExistingBookingBuilder do
  subject(:builder) { described_class.new(hotel: build_stubbed(:hotel), context: context) }

  let(:context) { {} }

  it "builds the secure confirmation-code prompt" do
    expect(builder.call(:ask_existing_booking_confirmation_code)).to eq(
      "Enter your booking confirmation code. You can find it in your booking email."
    )
  end

  it "builds the cancellation portal offer" do
    expect(builder.call(:existing_booking_cancellation_portal)).to eq(
      "You can submit an eligible cancellation and refund request through the Guest Portal. " \
        "I can send a secure login link to the email saved on your booking."
    )
  end

  it "builds the invalid-code retry" do
    expect(builder.call(:existing_booking_not_found)).to eq(
      "I could not send a login link with that confirmation code. Check the code and try again."
    )
  end

  it "builds the post-link support reply with a masked destination" do
    message = described_class.new(
      hotel: build_stubbed(:hotel),
      context: { masked_email: "j•••@example.com" }
    ).call(:magic_link_sent)

    expect(message).to eq(
      "Your secure login link is on its way to j•••@example.com. Open it to manage your booking. " \
        "I am here if you need more help."
    )
  end

  it "builds the cooldown reply with a masked destination" do
    message = described_class.new(
      hotel: build_stubbed(:hotel),
      context: { masked_email: "j•••@example.com" }
    ).call(:magic_link_cooldown)

    expect(message).to eq(
      "A login link was already sent to j•••@example.com. Please wait two minutes before you request another link."
    )
  end

  it "builds the magic-link failure offer" do
    expect(builder.call(:magic_link_unavailable)).to eq(
      "I cannot send a login link for this booking, but the hotel team can help you here. " \
        "Would you like me to ask them to review your request?"
    )
  end

  it "builds the approved post-handoff support reply" do
    expect(builder.call(:booking_support_requested)).to eq(
      "I have asked the hotel team to help with your booking. They will reply here when available. " \
        "You can continue chatting while you wait."
    )
  end

  it "builds the positive date-change handoff offer" do
    expect(builder.call(:unsupported_date_change)).to eq(
      "Booking-date changes are not available in the Guest Portal yet. For now, I can ask the hotel team to help you " \
        "change your check-in date. Would you like me to contact them, or would you like help with something else?"
    )
  end

  it "builds a positive exception-review handoff offer" do
    expect(builder.call(:unsupported_exception)).to eq(
      "This request needs a review from the hotel team. I can ask them to help you here. " \
        "Would you like me to contact them, or would you like help with something else?"
    )
  end
end
