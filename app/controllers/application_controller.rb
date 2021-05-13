# frozen_string_literal: true

class ApplicationController < ActionController::Base
  def home; end

  def feed
    @posts = Post.published

    render formats: [:atom]
  end

  def current_user
    @current_user ||= User.find_by(id: session[:user_id])
  end
end
