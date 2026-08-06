# frozen_string_literal: true

class RefundRequestPresenter
  include ActionView::Helpers::NumberHelper

  attr_reader :refund_request

  def initialize(refund_request)
    @refund_request = refund_request
  end

  def account_type_options
    RefundRequest::ACCOUNT_TYPES.map { |t| [ t.humanize, t ] }
  end

  def suggested_amount_label(booking, eligibility)
    number_to_currency(
      eligibility.suggested_amount,
      unit: "#{booking.currency} "
    )
  end
end
