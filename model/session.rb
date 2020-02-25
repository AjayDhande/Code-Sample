class Session < ApplicationRecord
  include StatsConcern
  require 'user_agent_api'
  has_many :session_tracking_links, dependent: :destroy
  has_many :docs, through: :session_tracking_links
  has_many :tracking_links, through: :session_tracking_links
  belongs_to :receiver
  has_many :session_pages, class_name: 'Session::Page', dependent: :destroy
  has_many :session_page_clicks, class_name: 'Session::PageClick',
           through: :session_pages
  has_many :docs_files, class_name: 'Docs::File', through: :tracking_link
  has_many :docs_engagement_pages, class_name: 'Docs::EngagementPage',
           through: :doc

  serialize :browser_info, Hash
  serialize :ip_details, Hash

  scope :by_tl, -> (id) {joins(:session_tracking_links).where('session_tracking_links.tracking_link_id': id)}
  scope :by_doc, -> (id) {joins(:session_tracking_links).where('session_tracking_links.doc_id': id)}

  scope :viewed, -> {
      joins('INNER JOIN docs ON session_tracking_links.doc_id = docs.id')
        .having('secs >= page_viewed_sec')
        .order("#{:sessions}.created_at DESC")
        .select("#{:sessions}.*,page_viewed_sec,(SELECT SUM(s.seconds_on_page)
                FROM #{:session_pages} AS s
                WHERE s.session_id = #{:sessions}.id) AS secs")
  }

  scope :date_desc, -> () { order(:created_at => :desc) }

  IGNORE_UA = [
    'SkypeUriPreview', 'Google Favicon', 'Googlebot/2.1', 'GoogleWebLight',
    'Gluten Free Crawler', 'Mixmax-LinkPreview', 'Slackbot', 'Twitterbot',
    'help@dataminr.com', 'PaperLiBot/2.1', 'um-LN/1.0', 'BLEXBot/1.0',
    'swan/1.0', '+http://tweetedtimes.com', 'rv:1.9.0.9',
    'techinfo@ubermetrics-technologies.com', 'Baiduspider', 'LinkedInBot',
    'WhatsApp'
  ].freeze

  def self.blocked_ua(ua_string)
    self::IGNORE_UA.any? { |ua| ua_string.include?(ua) }
  end

  def process
    if 0 === self.browser_info.length
      ua = UserAgetApi.decodeUserAgent(self.ua_string)
      return if ua.nil?
      self.browser = ua['ua_family']
      self.os = ua['os']
      self.os_family = ua['os_family']
      self.device = ua['device_class']
      self.browser_info = {
          browser: ua['ua'],
          browser_version: ua['ua_version'],
          browser_icon: ua['ua_family_icon'],
          os_icon: ua['os_icon'],
          os_family: ua['os_family'],
          device: ua['device_class'],
          device_icon: ua['device_class_icon'],
          device_brand: ua['device_brand'],
          device_brand_icon: ua['device_brand_icon']
      }
      self.save
    end
    if 0 === self.ip_details.length
      ip_info = IpInfoApi.getIpInfo(self.ip)
      return if ip_info.nil?
      if ip_info[:error].nil?
        self.country = ip_info[:country]
        self.city = ip_info[:city]
        self.subdivision = ip_info[:subdivision]
        self.continent = ip_info[:continent]
        self.ip_details = ip_info
      else
        self.ip_details = ip_info
      end
      self.save
    end
  end

  def self.table_name
    'sessions'
  end

  # stats functions

  def get_pages_viewed (stats_for, as = 'percent')
    case stats_for[:type]
    when 'tracking_link'
      tl = TrackingLink.find(stats_for[:id])
      condition = "session_tracking_links.tracking_link_id = #{stats_for[:id]}"
      docs_file = Docs::File.by_doc_and_lang(tl.doc_id, tl.language).first
    when 'doc'
      condition = "session_tracking_links.doc_id = #{stats_for[:id]}"
      docs_file = Docs::File.where(doc_id: stats_for[:id]).first
    end
    values = Statistics::get_percent_viewed(self.id,:session_id,
                                            condition)

    case as
      when 'percent'
        values[:pages] > 0 ? (Float(values[:pages]) / (values[:sessions] * docs_file.num_pages)) * 100 : 0
      when 'number'
        values[:pages] > 0 ? (Float(values[:pages]) / (values[:sessions])).round : 0
    end

  end

  def get_secs_viewed(as = 'avg')
    values = Statistics::get_secs_viewed(self.id,:session_id, stats_condition(:session_pages))

    if 'avg' === as
      values[:secs] > 0 ? (Float(values[:secs]) / values[:sessions]) : 0
    else
      values[:secs]
    end
  end

  def get_engagement(stats_for, as = 'percent')
    # engagement = Statistics::get_engagement(:session_id,stats_condition)
    score = engagement(stats_for,stats_condition)
    if as == 'percent'
      score = score > 0 ? score * 100 : 0
    elsif as =='number'
      score = score > 0 ? score.round : 0
    end
    score
  end

  def get_popular_pages
    Statistics::get_popular_pages(self.id,:session_id)
  end

  def get_pages_by_most_time_spent
    Statistics::get_pages_by_time_spent(self.id, :session_id)
  end

  def get_exit_page(stats_for)
    exit_page(stats_for, stats_condition)
  end

  def get_page_secs_viewed
    values = Statistics::get_page_secs_viewed(stats_condition,'session_pages.page')

    values[:secs] > 0 ? (Float(values[:secs]) / values[:pages]) : 0
  end

  def get_secs_viewed_by_page(sort_val = 'total_secs', sort_order = 'desc')
    page_info = Statistics::get_secs_viewed_by_page(stats_condition)
    page_info.each_with_index do |page, idx|
      page_info[idx][:total_secs] = page[:secs]
      page_info[idx][:secs] = page[:secs] > 0 ? (Float(page[:secs]) / page[:views]) : 0
    end

    page_info.sort_by! { |hsh| hsh[sort_val.to_sym] }

    if 'desc' === sort_order
      page_info.reverse!
    end
  end

  def get_elements_click
    Statistics::get_elements_click(stats_condition)
  end

  def filter_pages_viewed (stats_for, as = 'percent', threshold)
    case stats_for[:type]
    when 'tracking_link'
      tl = TrackingLink.find(stats_for[:id])
      condition = "session_tracking_links.tracking_link_id = #{stats_for[:id]}"
      docs_file = Docs::File.by_doc_and_lang(tl.doc_id, tl.language).first
    when 'doc'
      condition = "session_tracking_links.doc_id = #{stats_for[:id]}"
      docs_file = Docs::File.where(doc_id: stats_for[:id]).first
    end
    values = StatisticsFilter::get_percent_viewed(self.id,:session_id, condition, threshold)

    case as
      when 'percent'
        values[:pages] > 0 ? (Float(values[:pages]) / (values[:sessions] * docs_file.num_pages)) * 100 : 0
      when 'number'
        values[:pages] > 0 ? (Float(values[:pages]) / (values[:sessions])).round : 0
    end

  end

  def filter_secs_viewed(as = 'avg', threshold)
    values = StatisticsFilter::get_secs_viewed(self.id,:session_id, stats_condition(:session_pages), threshold)

    if 'avg' === as
      values[:secs] > 0 ? (Float(values[:secs]) / values[:sessions]) : 0
    else
      values[:secs]
    end
  end

  def filter_pages_by_most_time_spent(threshold)
    StatisticsFilter::get_pages_by_time_spent(self.id, :session_id, threshold)
  end

  def filter_popular_pages(threshold)
    StatisticsFilter.get_popular_pages(id, :doc_id, stats_condition(:session_pages), threshold)
  end

  def filter_secs_viewed_by_page(threshold, sort_val = 'total_secs', sort_order = 'desc')
    page_info = StatisticsFilter::get_secs_viewed_by_page(stats_condition, threshold)
    page_info.each_with_index do |page, idx|
      page_info[idx][:total_secs] = page[:secs]
      page_info[idx][:secs] = page[:secs] > 0 ? (Float(page[:secs]) / page[:views]) : 0
    end

    page_info.sort_by! { |hsh| hsh[sort_val.to_sym] }

    if 'desc' === sort_order
      page_info.reverse!
    end

  end

  private
  def stats_condition(table_name=:session_pages)
    "#{table_name}.session_id = #{self.id}"
  end

end
