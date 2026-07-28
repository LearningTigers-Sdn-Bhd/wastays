# frozen_string_literal: true

module DocumentIdentifiers
  class Issuer
    Allocation = Data.define(:number, :year, :reference)

    def self.issue!(hotel:, type:, year: sequence_year(hotel:))
      definition = Catalog.fetch(type)
      number = HotelCounter.increment!(
        hotel:,
        type: definition.fetch(:counter),
        year:,
        floor: floor(hotel:, type: type.to_sym, year:)
      )
      Allocation.new(number:, year:, reference: format(hotel:, type:, year:, number:))
    end

    def self.next_number!(hotel:, type:, year: sequence_year(hotel:))
      issue!(hotel:, type:, year:).number
    end

    def self.format(hotel:, type:, year:, number:)
      return if year.blank? || number.blank?

      HotelReferences.format(hotel:, year:, number:, type_code: Catalog.fetch(type).fetch(:code))
    end

    def self.sequence_year(hotel:)
      hotel.current_business_date.year
    rescue StandardError
      Time.current.in_time_zone(hotel.hotel_time_zone).year
    end

    def self.floor(hotel:, type:, year:)
      case type
      when :reservation
        maxima(
          [ Booking, :reservation_year ],
          [ GroupBooking, :reservation_year ],
          hotel:,
          year:,
          column: :reservation_number
        )
      when :receipt
        Receipt.where(hotel:, receipt_year: year).maximum(:receipt_number) if defined?(Receipt) && Receipt.table_exists?
      when :folio
        BookingFolio.where(hotel:, folio_year: year).maximum(:folio_number)
      when :invoice
        BookingFolio.where(hotel:, invoice_year: year).maximum(:invoice_number)
      when :ar_invoice
        ArInvoice.where(hotel:, invoice_year: year).maximum(:invoice_number)
      when :guest_registration
        Booking.where(hotel:, guest_registration_year: year).maximum(:guest_registration_number)
      when :tourism_tax_voucher
        Booking.where(hotel:, tourism_tax_voucher_year: year).maximum(:tourism_tax_voucher_number)
      end
    end

    def self.maxima(*models_and_year_columns, hotel:, year:, column:)
      models_and_year_columns.filter_map do |model, year_column|
        model.where(hotel:, year_column => year).maximum(column)
      end.max
    end

    private_class_method :floor, :maxima
  end
end
