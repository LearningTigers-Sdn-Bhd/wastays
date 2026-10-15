# frozen_string_literal: true

module Ezee
  # One reservation, in the shape every eZee report layout is read into.
  #
  # The importer behind the parsers (plan, preview, commit) only ever sees this,
  # so a new report layout is a new parser and nothing else. Everything below
  # `remark` is optional: the original Reservation List supplies none of it and
  # the planner falls back to its own rules, while a layout that can say it
  # directly (the reservation CSV) fills it in.
  ReservationRow = Struct.new(
    :sheet_row, :reservation_number, :booked_at, :source, :guest_name,
    :arrival, :departure, :adults, :children, :nights, :room_number,
    :room_type, :rate_type, :total_amount, :amount_paid, :user, :remark,
    :layout,         # :reservation_csv when the parser resolved the fields below itself
    :booking_status, # "confirmed" | "pending" | "cancelled" (nil means confirmed)
    :group_ref,      # the booking a multi-room stay belongs to, when the file says so
    :agency_name,    # the travel agent / corporate account, when the file says so
    :source_key,     # a BookingSource key, when the file says so
    :internal_note,  # staff-only context the parser wants kept on the booking
    :boat_in,        # { type: "provided"|"own"|"charter", time: "HH:MM" | nil }
    :boat_out,
    keyword_init: true
  ) do
    def cancelled? = booking_status.to_s == "cancelled"
    def explicit_layout? = layout == :reservation_csv
  end
end
