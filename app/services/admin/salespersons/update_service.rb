module Admin
  module Salespersons
    class UpdateService
      Result = Struct.new(:success?, :salesperson, :action, :error)

      def initialize(salesperson:, params:, hotel_ids:)
        @salesperson = salesperson
        @params = params
        @hotel_ids = hotel_ids
      end

      def call
        ActiveRecord::Base.transaction do
          if @salesperson.update(@params)
            if @hotel_ids.empty?
              detach_all_hotels
              @salesperson.destroy
              Result.new(true, @salesperson, :destroyed, nil)
            else
              sync_hotels
              Result.new(true, @salesperson, :updated, nil)
            end
          else
            Result.new(false, @salesperson, nil, @salesperson.errors.full_messages.to_sentence)
          end
        end
      rescue => e
        Result.new(false, @salesperson, nil, e.message)
      end

      private

      def detach_all_hotels
        Hotel.where(salesperson_id: @salesperson.id).update_all(salesperson_id: nil)
      end

      def sync_hotels
        detach_all_hotels
        Hotel.where(id: @hotel_ids).update_all(salesperson_id: @salesperson.id)
      end
    end
  end
end
