module Admin
  module Salespersons
    class CreateService
      Result = Struct.new(:success?, :salesperson, :error)

      def initialize(account:, params:, hotel_ids:)
        @account = account
        @params = params
        @hotel_ids = hotel_ids
      end

      def call
        salesperson = User.new(@params)
        salesperson.role = "salesperson"
        salesperson.account = @account
        salesperson.email = @params[:email].presence || generated_email
        salesperson.password ||= generated_password
        salesperson.password_confirmation ||= salesperson.password

        ActiveRecord::Base.transaction do
          if salesperson.save
            assign_hotels(salesperson)
            Result.new(true, salesperson, nil)
          else
            Result.new(false, salesperson, salesperson.errors.full_messages.to_sentence)
          end
        end
      rescue => e
        Result.new(false, salesperson, e.message)
      end

      private

      def assign_hotels(salesperson)
        Hotel.where(id: @hotel_ids).update_all(salesperson_id: salesperson.id)
      end

      def generated_email
        "salesperson-#{SecureRandom.hex(6)}@wastays.local"
      end

      def generated_password
        SecureRandom.hex(16)
      end
    end
  end
end
