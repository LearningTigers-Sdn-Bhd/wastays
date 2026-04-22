class AddOnboardingPeriodToHotels < ActiveRecord::Migration[8.0]
  def change
    add_column :hotels, :onboarding_start_date, :date
    add_column :hotels, :onboarding_end_date, :date
  end
end
