# frozen_string_literal: true

class ApplicationRecord < ActiveRecord::Base
  self.abstract_class = true

  private

  def url_helpers
    @url_helpers ||= Rails.application.routes.url_helpers
  end
end
