# frozen_string_literal: true

class EnablePgvector < ActiveRecord::Migration[8.0]
  def change
    enable_extension "vector" unless extension_enabled?("vector")
  end
end
