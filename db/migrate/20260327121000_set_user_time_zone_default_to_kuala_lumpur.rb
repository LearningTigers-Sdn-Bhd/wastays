class SetUserTimeZoneDefaultToKualaLumpur < ActiveRecord::Migration[8.0]
  def change
    change_column_default :users, :time_zone, from: "Asia/Kuching", to: "Kuala Lumpur"
  end
end
