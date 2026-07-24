# frozen_string_literal: true

module TransactionCodes
  # One place to answer "which transaction code does this belong to?".
  #
  # Before this existed the same `hotel.transaction_codes.find_by(system_key: …)`
  # was written out in two dozen places, and the tax-line resolution below was
  # copy-pasted byte-for-byte into four services — so adding a tax type meant
  # editing the same `case` four times.
  #
  # Build one per hotel and reuse it; found codes are memoized for the
  # resolver's lifetime. Misses are not cached, because a caller may create the
  # code (via Financials::EnsureDefaultTransactionCodes) between two lookups.
  class Resolver
    # Tax lines speak their own vocabulary — "sst", not "sst_tax". This map is
    # the only place the two are reconciled; a new tax type is one line here.
    TAX_TYPE_SYSTEM_KEYS = {
      "sst" => "sst_tax",
      "tourism_tax" => "tourism_tax"
    }.freeze

    def self.for(hotel)
      new(hotel)
    end

    def initialize(hotel)
      @hotel = hotel
      @by_system_key = {}
      @by_id = {}
    end

    def room_revenue
      for_key("room_revenue")
    end

    def for_key(system_key)
      return if system_key.blank?

      @by_system_key[system_key.to_s] ||= @hotel.transaction_codes.find_by(system_key: system_key.to_s)
    end

    def for_key!(system_key)
      for_key(system_key) || raise(ActiveRecord::RecordNotFound, "no transaction code with system_key #{system_key.inspect} for hotel #{@hotel.id}")
    end

    def for_id(id)
      return if id.blank?

      @by_id[id] ||= @hotel.transaction_codes.find_by(id: id)
    end

    # "sst" / "tourism_tax" as they appear in a tax line's `type`.
    def for_tax_type(tax_type)
      for_key(TAX_TYPE_SYSTEM_KEYS[tax_type.to_s])
    end

    # The code a tax line posts to: its own explicit code if the snapshot named
    # one, otherwise the standing code for its type.
    def for_tax_line(tax_line)
      tax_line = tax_line.to_h
      id = tax_line["transaction_code_id"].presence || tax_line[:transaction_code_id].presence
      return for_id(id) if id.present?

      for_tax_type(tax_line["type"].presence || tax_line[:type].presence)
    end

    # The code whose charge this tax was levied on — used to keep an attached tax
    # with its parent charge when routing. Nil when the snapshot did not record one.
    def source_for_tax_line(tax_line)
      tax_line = tax_line.to_h
      for_id(tax_line["source_transaction_code_id"].presence || tax_line[:source_transaction_code_id].presence)
    end
  end
end
