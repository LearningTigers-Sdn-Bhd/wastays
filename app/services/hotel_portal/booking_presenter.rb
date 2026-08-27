# frozen_string_literal: true

module HotelPortal
  class BookingPresenter
    attr_reader :booking, :hotel

    delegate :vip?, :blacklisted?, :repeat?, to: :booking

    def initialize(booking, hotel)
      @booking = booking
      @hotel = hotel
    end

    def confirmation_token
      booking.confirmation_token
    end

    def status
      booking.status
    end

    def status_label_class
      case status
      when "confirmed" then "border-green-800 text-green-800"
      when "no_show_detected" then "border-amber-800 text-amber-800"
      when "checked_in" then "border-blue-800 text-blue-800"
      when "due_out_detected" then "border-orange-800 text-orange-800"
      when "checkout_required" then "border-rose-800 text-rose-800"
      when "completed" then "border-emerald-800 text-emerald-800"
      when "cancelled" then "border-red-800 text-red-800"
      when "voided" then "border-red-800 text-red-800"
      when "pending" then "border-yellow-800 text-yellow-800"
      else "border-border-interactive text-foreground"
      end
    end

    def guarantee_method_display
      (booking.guarantee_method || "none").titleize
    end

    def created_at_formatted
      booking.created_at.strftime("%d %b %Y at %H:%M")
    end

    def check_in_formatted
      format_date(booking.check_in, :long)
    end

    def check_out_formatted
      format_date(booking.check_out, :long)
    end

    def nights_count
      (booking.check_out.to_date - booking.check_in.to_date).to_i
    end

    def nights_label
      view_context.pluralize(nights_count, "night")
    end

    def stay_summary
      "#{nights_count} #{'night'.pluralize(nights_count)} · #{check_in_short}–#{check_out_short}"
    end

    def guest_count_summary
      "#{booking.adults} #{'adult'.pluralize(booking.adults)} · #{booking.children.to_i} #{'child'.pluralize(booking.children.to_i)}"
    end

    def checked_in_at_form_value
      (booking.checked_in_at || default_check_in_moment).in_time_zone(hotel.hotel_time_zone).strftime("%Y-%m-%dT%H:%M")
    end

    # Past midnight the wall clock already reads tomorrow while the hotel still
    # trades yesterday, so "now" would open the sheet on the wrong day. An
    # arrival that still sits inside the open business date falls back to its
    # scheduled time instead; the desk can type the real arrival time over it.
    def default_check_in_moment
      arrival = booking.check_in
      return Time.current if arrival.blank?

      arrival_date = arrival.in_time_zone(hotel.hotel_time_zone).to_date
      return Time.current unless arrival_date < Time.current.in_time_zone(hotel.hotel_time_zone).to_date
      return Time.current if hotel.date_closed?(arrival_date)

      arrival
    end

    # Greys out every date after today in the calendar. It only teaches the
    # limit early: Bookings::ProcessCheckIn enforces it.
    def checked_in_at_max_value
      Time.current.in_time_zone(hotel.hotel_time_zone).strftime("%Y-%m-%dT%H:%M")
    end

    def check_in_business_date_hint
      business_date = hotel.current_business_date
      return if business_date.blank?

      "Posts to business date #{business_date.strftime('%d %b %Y')}."
    end

    def checked_out_at_form_value
      return booking.check_out.in_time_zone(booking.hotel.hotel_time_zone).strftime("%Y-%m-%dT%H:%M") if booking.checkout_required?

      Time.current.in_time_zone(hotel.hotel_time_zone).strftime("%Y-%m-%dT%H:%M")
    end

    def check_in_title
      booking.checked_in? ? "Edit Check-In" : "Confirm Check-In"
    end

    def requires_backdated_checkin_reason?
      hotel.date_closed?(booking.check_in.to_date)
    end

    def can_manage_bookings?(user)
      user.has_permission?("manage_bookings", hotel: hotel)
    end

    def can_add_guests?(user)
      can_manage_bookings?(user) && %w[checked_in confirmed].include?(booking.status)
    end

    def additional_guests
      @additional_guests ||= booking.booking_guests.select { |booking_guest| !booking_guest.is_primary? }
    end

    def registered_guest_count
      1 + additional_guests.size
    end

    def missing_guest_record_count
      [ booking.adults.to_i + booking.children.to_i - registered_guest_count, 0 ].max
    end

    def registered_guest_count_label
      view_context.pluralize(registered_guest_count, "registered guest")
    end

    def missing_guest_record_label
      "This booking has #{view_context.pluralize(missing_guest_record_count, 'guest')} that have not been added to the guest records."
    end

    def reference_ids
      [
        [ "Confirmation", confirmation_token ],
        [ "Reservation", booking.formatted_reservation_number ],
        [ "Folio Account", booking.folio_account_reference_display ],
        [ "Guest Registration", booking.formatted_guest_registration_number ],
        [ "External", booking.external_reference ],
        [ "Channel Manager", booking.channel_manager_reference ]
      ]
    end

    def primary_guest
      @primary_guest ||= booking.primary_guest
    end

    def guest_name
      booking.guest_name
    end

    def guest_email
      booking.guest_email
    end

    def guest_phone
      booking.guest_phone
    end


    def primary_guest_name
      primary_guest&.name.presence || booking.guest_name
    end

    def primary_guest_email
      primary_guest&.email.presence || booking.guest_email
    end

    def primary_guest_phone
      primary_guest&.phone.presence || booking.guest_phone
    end

    def primary_guest_country
      primary_guest&.country.presence || booking.guest_country.presence || "—"
    end

    def primary_guest_document_type
      primary_guest&.document_type.presence || booking.guest_document_type.presence || "IC/Passport"
    end

    def primary_guest_government_id
      primary_guest&.government_id.presence || booking.guest_government_id.presence || "—"
    end

    def primary_guest_email_display
      primary_guest_email.presence || "—"
    end

    def primary_guest_phone_display
      primary_guest_phone.presence || "—"
    end

    def primary_guest_document_type_display
      primary_guest_document_type.to_s.upcase
    end

    def guest_document_type_label(guest)
      guest.document_type&.upcase || "IC/Passport"
    end

    def pre_checkin_metadata
      @pre_checkin_metadata ||= (booking.pre_checkin&.metadata || {})
    end

    def estimated_arrival_time_label
      pre_checkin_metadata["estimated_arrival_time"].presence || booking.estimated_arrival_time.presence || "Not provided"
    end

    def guest_government_id_label
      pre_checkin_metadata["guest_government_id"].presence || "Not provided"
    end

    def current_room_number
      @current_room_number ||= booking.booking_rooms.first&.room_number.presence ||
                               (if booking.hotel_snapshot.is_a?(Hash)
                                  booking.hotel_snapshot["room_number"].presence || booking.hotel_snapshot.dig("assignment", "room_number").presence
                                end)
    end

    def payment_status_display
      status = booking.payment_status.to_s
      status == "refunded" ? "cancelled" : status
    end

    def payment_status_label_class
      display_status = payment_status_display
      case display_status
      when "captured", "completed" then "border-emerald-800 text-emerald-800"
      when "pending", "authorized" then "border-yellow-800 text-yellow-800"
      when "failed", "cancelled", "refunded" then "border-red-800 text-red-800"
      else "border-border-interactive text-foreground"
      end
    end

    def pre_checkin_display_status
      booking.pre_checkin_display_status
    end

    def pre_checkin_status_label_class
      case pre_checkin_display_status
      when "completed" then "border-green-800 text-green-800"
      when "in_progress" then "border-blue-800 text-blue-800"
      when "failed" then "border-red-800 text-red-800"
      when "pending" then "border-yellow-800 text-yellow-800"
      else "border-border-interactive text-foreground"
      end
    end

    def pre_checkin_badge_class
      if pre_checkin&.completed?
        "bg-emerald-50 text-emerald-700 ring-emerald-600/20"
      else
        "bg-amber-50 text-amber-700 ring-amber-600/20"
      end
    end

    def pre_checkin_badge_label
      if pre_checkin&.completed?
        "Pre-checked"
      else
        "Pending"
      end
    end

    def room_type_prices_json
      room_types.map { |rt| [ rt.id, rt.base_price ] }.to_h.to_json
    end

    def room_type_numbers_json
      directory = ::Rooms::DirectoryQuery.call(hotel:)
      room_types.map { |rt| [ rt.id, directory.numbers_for(rt.id) ] }.to_h.to_json
    end

    def room_types
      @room_types ||= hotel.room_types.order(:name)
    end

    def booking_rooms
      @booking_rooms ||= booking.booking_rooms
    end

    def room_total
      booking_rooms.sum { |room| room.subtotal.to_d }
    end

    def taxes_total
      booking.tax_total.to_d
    end

    def held_security_deposit_total
      @held_security_deposit_total ||= booking.deposits.kind_security.where(status: "held")
        .includes(:deposit_movements).sum(&:available_amount)
    end

    def projected_outstanding_balance
      (booking.booking_folio&.projected_outstanding_balance || 0).to_d
    end

    def balance_due?
      projected_outstanding_balance.positive?
    end

    def folio_forecast_count
      booking.booking_folio&.projected_forecasts&.count.to_i
    end

    def source_label
      booking.source.to_s.presence&.tr("_", " ")&.titleize || "—"
    end

    def room_summary
      summaries = booking_rooms.map do |room|
        name = room.room_type_snapshot["name"].presence || room.room_type&.name
        number = room_number_for(room)
        [ name, number.present? ? "Room #{number}" : nil ].compact.join(" · ")
      end

      summaries.reject(&:blank?).to_sentence.presence || "—"
    end

    def rate_plan_label
      booking_rooms.map { |room| room.rate_plan&.name }.compact.uniq.to_sentence.presence
    end

    def room_rate_label
      return 0.to_d unless nights_count.positive?

      (room_total / nights_count).round(2)
    end

    def room_number_for(room)
      room.room_number.presence ||
        (booking.hotel_snapshot.is_a?(Hash) ? booking.hotel_snapshot["room_number"].presence || booking.hotel_snapshot.dig("assignment", "room_number").presence : nil)
    end

    def pre_checkin
      @pre_checkin ||= booking.pre_checkin
    end

    def housekeeping_requests
      @housekeeping_requests ||= booking.housekeeping_requests
                                        .where(archived_at: nil)
                                        .or(booking.housekeeping_requests.where(status: "cancelled"))
                                        .recent_first
    end

    def pending_housekeeping_requests_count
      @pending_housekeeping_requests_count ||= booking.housekeeping_requests.active.where(status: "pending").count
    end

    def complaint_requests
      @complaint_requests ||= booking.complaint_requests
                                     .where(archived_at: nil)
                                     .or(booking.complaint_requests.where(status: "cancelled"))
                                     .recent_first
    end

    def pending_complaint_requests_count
      @pending_complaint_requests_count ||= booking.complaint_requests.active.where(status: "pending").count
    end

    def pending_requests_count
      pending_housekeeping_requests_count + pending_complaint_requests_count
    end

    # What the hotel's late-checkout policy charges this booking, pre-tax, or nil
    # when the policy names no figure (manual pricing, or not charging at all).
    # The server recomputes this on submit — the sheet only displays it.
    def late_checkout_policy_quote
      return @late_checkout_policy_quote if defined?(@late_checkout_policy_quote)

      @late_checkout_policy_quote = ReservationPolicies::Quote.call(booking: booking, policy_type: "late_checkout")
    end

    def late_checkout_policy_amount
      quote = late_checkout_policy_quote
      return nil unless quote.success?
      return nil if quote.amount.blank? || !quote.amount.positive?

      quote.amount
    end

    def late_checkout_policy_label
      late_checkout_policy_quote.success? ? late_checkout_policy_quote.label : nil
    end

    # Whether the sheet may offer "follow policy" at all. A manual or inactive
    # policy has no computed figure, so staff name the amount as they always have.
    def late_checkout_policy_amount? = late_checkout_policy_amount.present?

    # Pre-tax. A late-checkout charge now posts its taxes as separate lines using
    # ROOM's rules, so a suggestion with tax folded in would be taxed twice.
    def suggested_late_checkout_amount
      late_checkout_policy_amount || staff_entered_late_checkout_base
    end

    # The base the staff-entered ("custom") path builds its adjustment on when the
    # policy names no figure: today's rate for every room on the booking.
    def staff_entered_late_checkout_base
      primary_room = booking.booking_rooms.first
      return 0.to_d unless primary_room&.room_type

      room_type = primary_room.room_type
      today = Time.current.in_time_zone(hotel.hotel_time_zone).to_date
      rate = room_type.room_rates.find_by(date: today)&.price || room_type.base_price

      (rate.to_d * booking.booking_rooms.count).round(2)
    end

    def currency
      booking.currency.presence || "MYR"
    end

    def notes_json
      booking.booking_notes.includes(:user).map { |n|
        {
          body: n.body,
          author: n.user.name,
          date: n.created_at.strftime("%b %d, %Y %H:%M")
        }
      }.to_json
    end

    def guarantee_method_options
      Booking::GUARANTEE_METHODS.map { |m| [ m.titleize, m ] }
    end

    def can_request_refund?
      (booking.status == "cancelled" || booking.status == "confirmed") && booking.refund_request.blank?
    end

    def refund_eligibility
      @refund_eligibility ||= Refunds::Eligibility.new(booking).call
    end

    def occupancy_text(variant: :desktop)
      if variant == :desktop
        "#{booking.adults} #{'adult'.pluralize(booking.adults)} · #{booking.children.to_i} ch."
      else
        "#{booking.adults}A · #{booking.children.to_i}C"
      end
    end

    def room_display_text(variant: :desktop)
      primary_room = booking.booking_rooms.first
      return "—" unless primary_room

      room_no = room_number_for(primary_room)
      room_type = primary_room.room_type_snapshot["name"].presence || primary_room.room_type&.name

      if variant == :desktop
        room_no.present? ? "Room #{room_no} · #{room_type}" : room_type
      else
        room_no.present? ? "#{room_type} · #{room_no}" : room_type
      end
    end

    def formatted_projected_balance
      format_currency(projected_outstanding_balance)
    end

    def payment_status_label
      payment_status_display.to_s.tr("_", " ").titleize.presence || "—"
    end

    def guarantee_method_label
      booking.guarantee_method.to_s.presence&.tr("_", " ")&.titleize || "No guarantee"
    end

    def security_deposit_status_label
      booking.deposit_status.to_s.presence&.tr("_", " ")&.titleize || "Not Required"
    end

    def formatted_room_total
      format_currency(room_total)
    end

    def formatted_taxes_total
      format_currency(taxes_total)
    end

    def formatted_held_security_deposit_total
      format_currency(held_security_deposit_total)
    end

    def formatted_total_amount
      format_currency(booking.total_amount)
    end

    def guest_name_initial
      booking.guest_name&.chr || "G"
    end

    def primary_room_type_name
      booking.booking_rooms.first&.room_type&.name || "Room"
    end

    def formatted_check_in_date
      format_date(booking.check_in, :short_month_day)
    end

    def formatted_check_out_date
      format_date(booking.check_out, :short_month_day)
    end

    def dashboard_status_badge_class
      case status
      when "confirmed" then "bg-emerald-50 text-emerald-700 ring-emerald-600/20"
      when "cancelled" then "bg-red-50 text-red-700 ring-red-600/20"
      else "bg-muted text-foreground ring-ring/20"
      end
    end

    def dashboard_status_label
      status.titleize
    end

    def formatted_total_amount_dashboard
      "RM #{view_context.number_with_precision(booking.total_amount, precision: 2, delimiter: ",")}"
    end

    def self.status_pill_style(status)
      booking_pill_styles = {
        "pending" => "peer-checked:border-amber-400 peer-checked:bg-amber-50 peer-checked:text-amber-700 peer-checked:hover:bg-amber-100",
        "confirmed" => "peer-checked:border-blue-400 peer-checked:bg-blue-50 peer-checked:text-blue-700 peer-checked:hover:bg-blue-100",
        "no_show_detected" => "peer-checked:border-amber-500 peer-checked:bg-amber-50 peer-checked:text-amber-800 peer-checked:hover:bg-amber-100",
        "checked_in" => "peer-checked:border-violet-400 peer-checked:bg-violet-50 peer-checked:text-violet-700 peer-checked:hover:bg-violet-100",
        "due_out_detected" => "peer-checked:border-orange-400 peer-checked:bg-orange-50 peer-checked:text-orange-700 peer-checked:hover:bg-orange-100",
        "checkout_required" => "peer-checked:border-rose-400 peer-checked:bg-rose-50 peer-checked:text-rose-700 peer-checked:hover:bg-rose-100",
        "completed" => "peer-checked:border-emerald-400 peer-checked:bg-emerald-50 peer-checked:text-emerald-700 peer-checked:hover:bg-emerald-100",
        "cancelled" => "peer-checked:border-border-interactive peer-checked:bg-muted peer-checked:text-foreground peer-checked:hover:bg-muted",
        "voided" => "peer-checked:border-destructive/30 peer-checked:bg-destructive/10 peer-checked:text-destructive",
        "no_show" => "peer-checked:border-rose-400 peer-checked:bg-rose-50 peer-checked:text-rose-700 peer-checked:hover:bg-rose-100",
        "overbooked" => "peer-checked:border-red-400 peer-checked:bg-red-50 peer-checked:text-red-700 peer-checked:hover:bg-red-100",
        "not_ready" => "peer-checked:border-red-400 peer-checked:bg-red-50 peer-checked:text-red-700 peer-checked:hover:bg-red-100"
      }
      booking_pill_styles[status] || "peer-checked:bg-primary peer-checked:text-primary-foreground peer-checked:border-border-interactive"
    end

    def created_at_date
      format_date(booking.created_at.in_time_zone(hotel.hotel_time_zone), :long)
    end

    def status_variant_class
      booking_styles = {
        "pending" => "border-warning/30 bg-warning/10 text-warning",
        "confirmed" => "border-info/30 bg-info/10 text-info",
        "no_show_detected" => "border-warning/30 bg-warning/10 text-warning",
        "checked_in" => "border-success/30 bg-success/10 text-success",
        "due_out_detected" => "border-warning/30 bg-warning/10 text-warning",
        "checkout_required" => "border-destructive/30 bg-destructive/10 text-destructive",
        "completed" => "border-success/30 bg-success/10 text-success",
        "cancelled" => "border-border-interactive bg-muted text-muted-foreground",
        "voided" => "border-destructive/30 bg-destructive/10 text-destructive",
        "no_show" => "border-destructive/30 bg-destructive/10 text-destructive",
        "overbooked" => "border-destructive/30 bg-destructive/10 text-destructive",
        "not_ready" => "border-destructive/30 bg-destructive/10 text-destructive"
      }
      booking_styles[status] || "border-border bg-muted text-muted-foreground"
    end

    def status_label_humanized
      status.humanize
    end

    def check_in_short
      format_date(booking.check_in, :short_day_month)
    end

    def check_out_short
      format_date(booking.check_out, :short_day_month)
    end

    def check_out_date_year
      check_out_formatted
    end

    def formatted_currency_total
      "#{currency} #{view_context.number_with_precision(booking.total_amount, precision: 2, delimiter: ",")}"
    end

    def guest_email_display
      booking.guest_email.presence || "—"
    end

    def guest_phone_display
      booking.guest_phone.presence || "—"
    end

    private

    def format_date(date, style)
      return "" if date.blank?

      case style
      when :long
        view_context.format_date(date)
      when :short_day_month
        date.strftime("%d %b")
      when :short_month_day
        date.strftime("%b %d")
      else
        date.to_s
      end
    end

    def format_currency(amount)
      "#{currency} #{view_context.number_with_precision(amount, precision: 2, delimiter: ",")}"
    end

    def view_context
      @view_context ||= begin
        h = ApplicationController.helpers
        h.extend(ApplicationHelper) unless h.respond_to?(:format_date)
        h
      end
    end
  end
end
