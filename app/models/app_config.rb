class AppConfig < ApplicationRecord
  encrypts :value

  validates :key, presence: true, uniqueness: true

  def self.get(key)
    return nil unless table_exists?

    find_by(key: key)&.value
  rescue ActiveRecord::StatementInvalid
    nil
  end

  def self.set(key, value)
    find_or_initialize_by(key: key).tap do |config|
      config.value = value
      config.save!
    end
  end
end
