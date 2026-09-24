# frozen_string_literal: true

module Admin::Hotels
  class UpdateSalesperson
    def self.call(hotel:, account:, operation:, salesperson_id:, name:, email:)
      ActiveRecord::Base.transaction do
        case operation
        when "assign"
          salesperson = account.users.find_by!(id: salesperson_id, role: "salesperson") if salesperson_id.present?
          hotel.update!(salesperson:)
        when "create"
          salesperson = account.users.create!(role: "salesperson", name:, email:, password: SecureRandom.hex(16))
          hotel.update!(salesperson:)
        when "update_contact"
          salesperson = account.users.find_by!(id: hotel.salesperson_id, role: "salesperson")
          salesperson.update!(name:, email:)
        else
          raise ArgumentError, "Unknown salesperson action"
        end
      end
      true
    end
  end
end
