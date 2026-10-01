# frozen_string_literal: true

class ErrorEvent < ApplicationRecord
  validates :error_class, :severity, :occurred_at, presence: true
end
