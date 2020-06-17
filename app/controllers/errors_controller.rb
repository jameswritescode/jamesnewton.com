# frozen_string_literal: true

class ErrorsController < ApplicationController
  def internal_server_error
    @code = 500
    render :index, status: @code
  end

  def not_found
    @code = 404
    render :index, status: @code
  end

  def unprocessable_entity
    @code = 422
    render :index, status: @code
  end
end
