class AddGuestAuthFields < ActiveRecord::Migration[8.0]
  def change
    add_column :guests, :otp_code_digest, :string
    add_column :guests, :otp_sent_at, :datetime
    add_column :guests, :magic_token_digest, :string
    add_column :guests, :magic_token_expires_at, :datetime
    add_column :guests, :last_signed_in_at, :datetime

    add_index :guests, :magic_token_digest, unique: true, where: "magic_token_digest IS NOT NULL"
  end
end
