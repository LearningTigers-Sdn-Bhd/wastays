module HotelPortal::BookingsHelper
  def hotel_payment_display_status(status)
    status.to_s == "refunded" ? "cancelled" : status
  end

  def hotel_payment_status_class(status)
    display_status = hotel_payment_display_status(status)
    return booking_status_class("cancelled") if display_status.to_s == "cancelled"

    payment_status_class(display_status)
  end

  def folio_transaction_amount_label(transaction, currency: nil)
    amount = transaction.amount.to_d
    signed_amount = case transaction.transaction_type
    when "charge" then amount
    when "payment" then -amount
    else amount
    end

    sign = signed_amount.negative? ? "-" : "+"
    currency_label = currency ? currency : " MYR"
    "#{sign}#{currency_label} #{number_with_precision(signed_amount.abs, precision: 2)}"
  end

  def folio_transaction_amount_class(transaction)
    amount = transaction.amount.to_d
    balance_effect = transaction.payment? ? -amount : amount

    balance_effect.negative? ? "text-emerald-600" : "text-slate-900"
  end
end
