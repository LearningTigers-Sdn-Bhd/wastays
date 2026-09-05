# frozen_string_literal: true

module StayView
  class ResolveFinancialSignals
    TERMINAL_BOOKING_STATUSES = %w[cancelled completed no_show voided].freeze

    FolioRecord = Data.define(:id, :booking_id, :status, :currency, :billing_party_id)
    PartyRecord = Data.define(
      :id, :kind, :account_type, :name, :settlement_type, :account_status, :direct_bill_enabled
    )
    InvoiceRecord = Data.define(:status, :amount, :currency)

    def self.call(hotel:, bookings:)
      new(hotel:, bookings:).call
    end

    def initialize(hotel:, bookings:)
      @hotel = hotel
      @bookings = bookings
    end

    def call
      return {} if booking_ids.empty?

      folios = load_folios
      return booking_ids.index_with { immutable_signals([ review_signal ]) } if folios.empty?

      transaction_totals = load_transaction_totals(folios.map(&:id))
      forecast_totals = load_forecast_totals(folios)
      invoices = load_invoices(folios.map(&:id))
      parties = load_parties(folios)
      folios.group_by(&:booking_id).each_with_object({}) do |(booking_id, booking_folios), result|
        result[booking_id] = immutable_signals(
          signals_for_booking(booking_folios, parties, invoices, transaction_totals, forecast_totals)
        )
      end.tap do |result|
        (booking_ids - result.keys).each { |booking_id| result[booking_id] = immutable_signals([ review_signal ]) }
      end
    end

    private

    attr_reader :hotel, :bookings

    def booking_ids
      @booking_ids ||= bookings.map(&:booking_id).uniq
    end

    def bookings_by_id
      @bookings_by_id ||= bookings.index_by(&:booking_id)
    end

    def load_folios
      BookingFolio.where(hotel_id: hotel.id, booking_id: booking_ids)
        .where.not(status: "voided")
        .order(:id)
        .pluck(:id, :booking_id, :status, :currency, :booking_billing_party_id)
        .map { |values| FolioRecord.new(*values) }
    end

    def load_parties(folios)
      party_ids = folios.filter_map(&:billing_party_id).uniq
      return {} if party_ids.empty?

      rows = BookingBillingParty.where(id: party_ids, hotel_id: hotel.id, booking_id: booking_ids)
        .pluck(:id, :party_kind, :account_type, :booking_guest_id, :hotel_corporate_account_id)
      guest_names = load_guest_names(rows.filter_map { |_id, kind, _type, guest_id, _account_id| guest_id if kind == "guest" })
      company_accounts = load_company_accounts(
        rows.filter_map { |_id, kind, _type, _guest_id, account_id| account_id if kind == "company" }
      )
      terms = BookingBillingTerms.where(booking_billing_party_id: party_ids)
        .pluck(:booking_billing_party_id, :settlement_type).to_h

      rows.to_h do |party_id, kind, account_type, booking_guest_id, hotel_corporate_account_id|
        account = company_accounts[hotel_corporate_account_id]
        name = kind == "guest" ? guest_names[booking_guest_id] : account&.fetch(:name, nil)
        [
          party_id,
          PartyRecord.new(
            id: party_id,
            kind:,
            account_type: account_type.presence || account&.fetch(:account_type, nil),
            name: name.to_s.presence,
            settlement_type: terms[party_id],
            account_status: account&.fetch(:status, nil),
            direct_bill_enabled: account&.fetch(:direct_bill_enabled, false) || false
          )
        ]
      end
    end

    def load_guest_names(booking_guest_ids)
      return {} if booking_guest_ids.empty?

      BookingGuest.left_joins(:guest).where(id: booking_guest_ids, booking_id: booking_ids)
        .pluck("booking_guests.id", Arel.sql("COALESCE(booking_guests.name_snapshot, guests.name)"))
        .to_h
    end

    def load_company_accounts(account_ids)
      return {} if account_ids.empty?

      HotelCorporateAccount.left_joins(:corporate_account).where(id: account_ids, hotel_id: hotel.id)
        .pluck(
          "hotel_corporate_accounts.id", "hotel_corporate_accounts.status",
          "hotel_corporate_accounts.direct_bill_enabled", "hotel_corporate_accounts.account_type", "accounts.name"
        )
        .to_h do |id, status, direct_bill_enabled, account_type, name|
          [ id, { status:, direct_bill_enabled:, account_type:, name: } ]
        end
    end

    def load_transaction_totals(folio_ids)
      FolioTransaction.where(booking_folio_id: folio_ids)
        .group(:booking_folio_id, :transaction_type)
        .sum(:amount)
    end

    def load_forecast_totals(folios)
      booking_id_by_folio_id = folios.filter_map do |folio|
        [ folio.id, folio.booking_id ] if folio.status == "open"
      end.to_h
      return {} if booking_id_by_folio_id.empty?

      FolioForecastedCharge.forecast
        .where(booking_folio_id: booking_id_by_folio_id.keys)
        .group(:booking_folio_id, :stay_date)
        .sum(:amount)
        .each_with_object(Hash.new(0.to_d)) do |((folio_id, stay_date), amount), totals|
          booking = bookings_by_id.fetch(booking_id_by_folio_id.fetch(folio_id))
          next if booking.status.to_s.in?(TERMINAL_BOOKING_STATUSES)
          next unless stay_date < booking.check_out

          totals[folio_id] += amount.to_d
        end
    end

    def load_invoices(folio_ids)
      ArInvoice.where(hotel_id: hotel.id, booking_folio_id: folio_ids)
        .pluck(:booking_folio_id, :status, :amount, :currency)
        .to_h { |folio_id, status, amount, currency| [ folio_id, InvoiceRecord.new(status:, amount:, currency:) ] }
    end

    def signals_for_booking(folios, parties, invoices, transaction_totals, forecast_totals)
      signals = []
      unassigned, assigned = folios.partition { |folio| folio.billing_party_id.blank? }
      if unassigned.any? { |folio| invoices.key?(folio.id) || projected_total(folio.id, transaction_totals, forecast_totals).nonzero? }
        signals << review_signal
      end

      assigned.group_by(&:billing_party_id).each_value do |party_folios|
        party = parties[party_folios.first.billing_party_id]
        signals.concat(
          party ? signals_for_party(party, party_folios, invoices, transaction_totals, forecast_totals) : [ review_signal ]
        )
      end

      signals = signals.uniq { |signal| [ signal.state, signal.label ] }
      signals.presence || [ settled_signal ]
    end

    def signals_for_party(party, folios, invoices, transaction_totals, forecast_totals)
      return [ party_review_signal(party) ] unless valid_party?(party)
      return [ direct_bill_review_signal(party) ] if invalid_invoice_state?(party, folios, invoices)

      billed, current = folios.partition { |folio| valid_billed_folio?(party, folio, invoices[folio.id]) }
      billed_totals = billed.each_with_object(Hash.new(0.to_d)) do |folio, totals|
        invoice = invoices.fetch(folio.id)
        totals[invoice.currency.to_s.upcase] += invoice.amount.to_d
      end
      current_folios_by_currency = Hash.new { |hash, key| hash[key] = [] }
      current_totals = current.each_with_object(Hash.new(0.to_d)) do |folio, totals|
        amount = projected_total(folio.id, transaction_totals, forecast_totals)
        next if amount.zero?

        currency = folio.currency.to_s.upcase
        totals[currency] += amount
        current_folios_by_currency[currency] << folio
      end
      currencies = (billed_totals.keys + current_totals.keys).uniq
      return [ party_review_signal(party) ] if currencies.many?

      signals = billed_totals.map do |currency, amount|
        direct_billed_signal(party, amount, currency)
      end
      current_totals.each do |currency, amount|
        signals << current_signal(party, current_folios_by_currency.fetch(currency), amount, currency)
      end
      signals.compact
    end

    def invalid_invoice_state?(party, folios, invoices)
      folios.any? do |folio|
        invoice = invoices[folio.id]
        next false unless invoice

        invoice.status == "void" || folio.status != "closed" || party.kind != "company"
      end
    end

    def valid_billed_folio?(party, folio, invoice)
      party.kind == "company" && folio.status == "closed" && invoice.present? && invoice.status != "void"
    end

    def current_signal(party, folios, amount, currency)
      return credit_signal(party, amount.abs, currency) if amount.negative?
      return balance_due_signal(party, amount, currency) unless party.settlement_type == "city_ledger"
      return direct_bill_review_signal(party) unless direct_bill_eligible?(party) && folios.all? { |folio| folio.status == "open" }

      direct_bill_planned_signal(party, amount, currency)
    end

    def valid_party?(party)
      party.name.present? && party.kind.in?(%w[guest company])
    end

    def direct_bill_eligible?(party)
      party.kind == "company" && party.account_status == "active" && party.direct_bill_enabled
    end

    def projected_total(folio_id, transaction_totals, forecast_totals)
      transaction_totals.fetch([ folio_id, "charge" ], 0).to_d -
        transaction_totals.fetch([ folio_id, "payment" ], 0).to_d +
        transaction_totals.fetch([ folio_id, "adjustment" ], 0).to_d +
        forecast_totals.fetch(folio_id, 0).to_d
    end

    # Labels lead with what the front desk should do, then the amount, then who
    # it concerns — so a glance answers "collect or not?" without folio jargon.
    def balance_due_signal(party, amount, currency)
      action = party.kind == "guest" ? "Collect" : "Unpaid"
      FinancialSignal.new(state: :balance_due, label: "#{action} #{money(amount, currency)} · #{party.name}")
    end

    def credit_signal(party, amount, currency)
      FinancialSignal.new(state: :credit, label: "Refund #{money(amount, currency)} · #{party.name}")
    end

    def direct_bill_planned_signal(party, amount, currency)
      FinancialSignal.new(state: :direct_bill_planned, label: "Company pays #{money(amount, currency)} · #{party.name}")
    end

    def direct_billed_signal(party, amount, currency)
      FinancialSignal.new(state: :direct_billed, label: "Invoiced #{money(amount, currency)} · #{party.name}")
    end

    def direct_bill_review_signal(party)
      FinancialSignal.new(state: :review, label: "Check billing · #{party.name}")
    end

    def party_review_signal(party)
      label = party.name.present? ? "Check folio · #{party.name}" : "Check folio"
      FinancialSignal.new(state: :review, label:)
    end

    def settled_signal
      FinancialSignal.new(state: :settled, label: "Nothing due")
    end

    def review_signal
      FinancialSignal.new(state: :review, label: "Check folio")
    end

    def money(amount, currency)
      CurrencyFormatter.format(amount, currency:, unit: :code)
    end

    def immutable_signals(signals)
      Immutable.array(signals)
    end
  end
end
