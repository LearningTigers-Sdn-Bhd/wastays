# frozen_string_literal: true

class BankCatalog
  MALAYSIAN_BANKS = [
    "Affin Bank",
    "Agrobank",
    "Alliance Bank",
    "AmBank",
    "Bank Islam",
    "Bank Muamalat",
    "Bank Rakyat",
    "Bank Simpanan Nasional",
    "CIMB",
    "Hong Leong Bank",
    "HSBC",
    "Maybank",
    "OCBC Bank",
    "Public Bank",
    "RHB",
    "Standard Chartered Bank",
    "UOB"
  ].freeze

  # The value a guest picks when their bank is not listed. They then type the
  # name, which is what gets stored.
  OTHER = "Other"

  class << self
    def listed?(name) = MALAYSIAN_BANKS.include?(name.to_s.strip)

    def options(current: nil)
      names = MALAYSIAN_BANKS.dup
      names << current.to_s.strip if current.present? && names.exclude?(current.to_s.strip)

      names.map { |name| [ name, name ] }
    end
  end
end
