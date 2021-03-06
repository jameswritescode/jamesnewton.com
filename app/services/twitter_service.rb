# frozen_string_literal: true

class TwitterService
  include ActionView::Helpers::DateHelper

  TWEET_URL = 'https://api.twitter.com/1.1/statuses/user_timeline/jameswritescode.json?count=10'

  DEFAULT_TWEET = {
    'created_at' => Time.current.to_s,
    'text' => 'There was an error pulling my latest tweet',
  }.freeze

  def content
    tweet['text']
  end

  def created
    ago = time_ago_in_words(DateTime.parse(tweet['created_at']))

    "#{ago} ago"
  end

  private

  def access_token
    credentials = Rails.application.credentials[:twitter]

    OAuth::AccessToken.from_hash(
      OAuth::Consumer.new(
        credentials[:api_key],
        credentials[:api_secret],
        scheme: :header,
        site: 'http://api.twitter.com',
      ),
      credentials.slice(:oauth_token, :oauth_token_secret),
    )
  end

  def find_tweet(tweet)
    !tweet['retweeted'] && !tweet['in_reply_to_status_id']
  end

  def tweet
    @tweet ||= begin
      Rails.cache.fetch('latest_tweet', expires_in: 1.hour) do
        result = JSON.parse(access_token.get(TWEET_URL).body).find(&method(:find_tweet))

        raise if result['text'].blank?

        result
      end
    rescue StandardError # rubocop:disable Layout/RescueEnsureAlignment
      DEFAULT_TWEET
    end
  end
end
