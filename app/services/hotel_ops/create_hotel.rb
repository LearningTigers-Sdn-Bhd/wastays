module HotelOps
  class CreateHotel
    def initialize(account_params:, user_params:, hotel_params:)
      @account_params = account_params
      @user_params = user_params
      @hotel_params = hotel_params
    end

    def call
      ActiveRecord::Base.transaction do
        account = Account.create!(@account_params.merge(status: 'active'))
        
        # Seed account roles
        SeedAccountRoles.call(account)
        
        user = User.create!(@user_params.merge(account: account, role: 'admin'))
        
        # Assign hotel owner role to user at account level
        owner_role = Role.find_by!(account: account, slug: 'hotel_owner')
        UserRole.create!(user: user, role: owner_role)
        
        hotel = Hotel.create!(@hotel_params.merge(account: account, status: 'registered'))
        
        # Grant hotel access with the owner role
        UserHotelAccess.create!(user: user, hotel: hotel, role: owner_role)
        
        { success: true, user: user, hotel: hotel, account: account }
      end
    rescue ActiveRecord::RecordInvalid => e
      { success: false, error: e.message }
    end
  end
end
