module Admin
  class SyncHotelSalesperson
    def initialize(hotel:, name:, email:, current_user:)
      @hotel = hotel
      @name = name.to_s.strip
      @email = email.to_s.strip
      @current_user = current_user
    end

    def call
      ActiveRecord::Base.transaction do
        salesperson = find_or_create_salesperson
        update_hotel_salesperson(salesperson) if salesperson
      end
    end

    private

    def find_or_create_salesperson
      salesperson = @hotel.salesperson

      if salesperson.blank? && @name.present?
        salesperson = @current_user.account.users.find_by(role: "salesperson", name: @name)
      end

      if salesperson
        updates = {}
        updates[:name] = @name if @name.present? && salesperson.name != @name
        updates[:email] = @email if @email.present? && salesperson.email != @email
        salesperson.update!(updates) if updates.any?
      elsif @name.present?
        # Create new salesperson if they don't exist
        password = SecureRandom.hex(16)
        salesperson = @current_user.account.users.create!(
          role: "salesperson",
          name: @name,
          email: @email.presence || "salesperson-#{SecureRandom.hex(6)}@wastays.local",
          password: password,
          password_confirmation: password
        )
      end

      salesperson
    end

    def update_hotel_salesperson(salesperson)
      if @hotel.salesperson_id != salesperson.id
        @hotel.update!(salesperson_id: salesperson.id)
      end
    end
  end
end
