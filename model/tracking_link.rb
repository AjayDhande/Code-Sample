class TrackingLink < ApplicationRecord
  include AllowedResourceConcern
  include StatsConcern
  belongs_to :doc
  belongs_to :company
  belongs_to :user
  belongs_to :campaign
  belongs_to :docs_file, class_name: 'Docs::File', foreign_key: :docs_files_id
  has_and_belongs_to_many :tags
  has_many :session_pages, class_name: 'Session::Page', dependent: :destroy
  has_many :receiver_tracking_links, dependent: :destroy
  has_many :receivers, through: :receiver_tracking_links
  has_many :tracking_link_notification_receivers, dependent: :destroy,
           autosave: true
  has_one :tracking_link_option, dependent: :destroy
  has_many :docs_engagement_pages, class_name: 'Docs::EngagementPage',
           through: :doc

  has_many :session_tracking_links, dependent: :destroy
  has_many :sessions, through: :session_tracking_links, dependent: :destroy

  enum privacy_setting: {
      do_not_show: '0',
      do_not_track: '1',
      track_after_optin: '2'
  }

  default_scope { order("#{:tracking_links}.created_at DESC") }

  scope :by_user, ->(user_id) { where(user_id: user_id) }
  scope :by_company, ->(company_id) { where(company_id: company_id) }
  scope :by_campaign, ->(campaigns) { where(campaign_id: campaigns) }
  scope :is_template, ->(bln) { where(template: bln) }
  scope :by_tl_ids, ->(ids) { where(id: ids) }
  scope :by_id, ->(tl_id) { where(id: tl_id) }
  scope :by_doc_id, ->(doc_id) { where(doc_id: doc_id) }
  scope :by_doc_name, ->(title) {
    # joins(:doc).select('title').where('title LIKE ?', "#{title}%")
    joins(:doc).select('title').where('MATCH(title) AGAINST(? IN BOOLEAN MODE)', "#{title}*")
  }
  scope :by_token, ->(token) { where('MATCH(token) AGAINST(? IN BOOLEAN MODE)', "#{token}*") }
  scope :by_name, ->(name) { where('MATCH(name) AGAINST(? IN BOOLEAN MODE)', "#{name}*") }
  # scope :by_tag, -> (tags) {
  #   ids = []
  #   Tag.where(:id => tags).map{ |tag| tag.tracking_links.map{ |tl| ids<<tl.id}}
  #   where(:id => ids )
  # }

  def get_tag_ids
    tag_ids = []
    self.tags.map { |tag| tag_ids << tag.id }
    tag_ids
  end

  def remove
    self.receivers.clear
    self.tracking_link_notification_receivers.clear
    self.destroy
  end

  def get_optins
    Statistics::get_optins(stats_condition)
  end

  def get_viewers
    Statistics::get_viewers(stats_condition)
  end

  def get_pages_viewed (as = 'percent')
    values = Statistics::get_percent_viewed(self.id,:tracking_link_id)
    docs_file = Docs::File.by_doc_and_lang(self.doc_id, Language::get_key_by_locale(self.language)).first

    case as
      when 'percent'
        values[:pages] > 0 ? (Float(values[:pages]) / (values[:sessions] * docs_file.num_pages)) * 100 : 0
      when 'number'
        values[:pages] > 0 ? (Float(values[:pages]) / (values[:sessions])).round : 0
    end

  end

  def get_secs_viewed(as = 'avg')
    values = Statistics::get_secs_viewed(self.id,:tracking_link_id, stats_condition(:session_pages))

    if 'avg' == as
      values[:secs] > 0 ? (Float(values[:secs]) / values[:sessions]) : 0
    else
      values[:secs]
    end
  end

  def get_popular_pages
    Statistics::get_popular_pages(self.id,:tracking_link_id, stats_condition(:session_pages))
  end

  def get_pages_by_most_time_spent
    Statistics::get_pages_by_time_spent(self.id, :tracking_link_id, stats_condition(:session_pages))
  end

  def get_exit_pages(popular=true)
    # Statistics::get_exit_pages(self.id, 'session_tracking_links.tracking_link_id', stats_condition(), popular)
    exit_pages(stat_type, stats_condition(:session_pages), popular)
  end

  def get_page_secs_viewed
    values = Statistics::get_page_secs_viewed(stats_condition,'session_pages.page')

    values[:secs] > 0 ? (Float(values[:secs]) / values[:pages]) : 0
  end

  def get_returning_viewers
    Statistics::get_returning_viewers(stats_condition)
  end

  def get_engagement(as = 'percent')
    # engagement = Statistics::get_engagement(:tracking_link_id, stats_condition(:session_pages), doc.docs_files.first.num_pages)
    score = engagement(stat_type, stats_condition(:session_pages))
    if as == 'percent'
      score = score > 0 ? score * 100 : 0
    elsif as =='number'
      score = score > 0 ? score.round : 0
    end
    score
  end

  def session_info(field = 'country',
                   replace_null_with = 'Unknown',
                   max_items = 20,
                   over_max_name = 'Other')
    top_stats = Statistics.get_session_info(
      stats_condition, field,
      replace_null_with,
      max_items, over_max_name
    )
    drill_down_fields = {
      country: 'subdivision',
      subdivision: 'city',
      os_family: 'os'
    }
    unless drill_down_fields[field.to_sym].nil?
      top_stats.each_with_index do |val, idx|
        condition = "#{stats_condition} AND #{:sessions}.#{field} = '#{val[field.to_sym]}'"
        top_stats[idx][:drilldown] = Statistics.get_session_info(
          condition, drill_down_fields[field.to_sym],
          replace_null_with,
          max_items, over_max_name
        )
      end
    end
    top_stats
  end

  def get_secs_viewed_by_page(sort_val = 'total_secs', sort_order = 'desc')
    page_info = Statistics::get_secs_viewed_by_page(stats_condition(:session_pages))
    page_info.each_with_index do |page, idx|
      page_info[idx][:total_secs] = page[:secs]
      page_info[idx][:secs] = page[:secs] > 0 ? (Float(page[:secs]) / page[:views]) : 0
    end

    page_info.sort_by! { |hsh| hsh[sort_val.to_sym] }

    page_info.reverse! if 'desc' == sort_order
  end

  def get_page_viewers
    Statistics::get_page_viewers(stats_condition)
  end

  def get_elements_click
    Statistics::get_elements_click(stats_condition(:session_pages))
  end

  def filter_viewers(threshold)
    StatisticsFilter.get_viewers(stats_condition, threshold)
  end

  def filter_pages_viewed(as = 'percent', threshold)
    values = Statistics::get_percent_viewed(self.id,:tracking_link_id, threshold)
    docs_file = Docs::File.by_doc_and_lang(self.doc_id, Language::get_key_by_locale(self.language)).first

    case as
      when 'percent'
        values[:pages] > 0 ? (Float(values[:pages]) / (values[:sessions] * docs_file.num_pages)) * 100 : 0
      when 'number'
        values[:pages] > 0 ? (Float(values[:pages]) / (values[:sessions])).round : 0
    end

  end

  def filter_popular_pages(threshold)
    StatisticsFilter.get_popular_pages(id, :doc_id, stats_condition(:session_pages), threshold)
  end

  def filter_returning_viewers(threshold)
    StatisticsFilter.get_returning_viewers(stats_condition, threshold)
  end

  def filter_secs_viewed(as = 'avg', threshold)
    values = StatisticsFilter.get_secs_viewed(id, :doc_id, stats_condition(:session_pages), threshold)

    if as == 'avg'
      values[:secs] > 0 ? (Float(values[:secs]) / values[:sessions]) : 0
    else
      values[:secs]
    end
  end

  def filter_session_info(field = 'country',
                   replace_null_with = 'Unknown',
                   max_items = 20,
                   over_max_name = 'Other', threshold)
    top_stats = StatisticsFilter.get_session_info(
      stats_condition, field,
      replace_null_with,
      max_items, over_max_name,
      threshold
    )
    drill_down_fields = {
      country: 'subdivision',
      subdivision: 'city',
      os_family: 'os'
    }
    unless drill_down_fields[field.to_sym].nil?
      top_stats.each_with_index do |val, idx|
        condition = "#{stats_condition} AND sessions.#{field} = '#{val[field.to_sym]}'"
        top_stats[idx][:drilldown] = StatisticsFilter.get_session_info(
          condition, drill_down_fields[field.to_sym],
          replace_null_with,
          max_items, over_max_name,
          threshold
        )
      end
    end
    top_stats
  end

  def filter_secs_viewed_by_page(sort_val = 'total_secs', sort_order = 'desc', threshold)
    page_info = StatisticsFilter.get_secs_viewed_by_page(stats_condition(:session_pages), threshold)
    page_info.each_with_index do |page, idx|
      page_info[idx][:total_secs] = page[:secs]
      page_info[idx][:secs] = page[:secs] > 0 ? (Float(page[:secs]) / page[:views]) : 0
    end

    page_info.sort_by! { |hsh| hsh[sort_val.to_sym] }

    page_info.reverse! if sort_order == 'desc'
  end

  private
  def stats_condition(table_name=:session_tracking_links)
    "#{table_name}.tracking_link_id = #{self.id}"
  end

  def stat_type
    {
        type: 'tracking_link',
        id: id,
        id_field_name: 'tracking_link_id',
        num_pages: doc.docs_files.first.num_pages
    }
  end

end
