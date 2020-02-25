#
class Doc < ApplicationRecord
  include AllowedResourceConcern
  include StatsConcern
  belongs_to :user
  belongs_to :company
  has_one :user_sampledoc, dependent: :destroy  
  has_and_belongs_to_many :tags, join_table: 'tags_docs'
  has_many :docs_files, class_name: 'Docs::File', dependent: :destroy
  has_many :docs_elements, class_name: 'Docs::Element', dependent: :destroy
  has_many :docs_lightboxes, class_name: 'Docs::Lightbox', dependent: :destroy
  has_many :tracking_links, dependent: :destroy
  has_many :receivers, through: :tracking_links
  has_many :docs_editor_live_files, class_name: 'Docs::EditorLiveFile',
                                    dependent: :destroy
  has_many :docs_engagement_pages, class_name: 'Docs::EngagementPage',
                                   dependent: :destroy
  has_many :docs_lightboxes, class_name: 'Docs::Lightbox', dependent: :destroy
  has_many :session_tracking_links, dependent: :destroy
  has_many :sessions, dependent: :destroy, through: :session_tracking_links

  after_destroy :remove_dir

  enum visibility: {
      to_all: 1,
      to_self: 2,
      partial: 3
  }

  validates_presence_of :title, :page_viewed_sec
  validates :title, uniqueness: { scope: :company_id, case_sensitive: false }, if: :skip_title_uniqness
  def skip_title_uniqness
    !self.title.downcase.start_with?('Sample KDF:'.downcase)
  end

  default_scope { order('created_at DESC') }

  scope :by_company, ->(company_id) { where(company_id: company_id) }
  scope :by_user, ->(user_id) { where(user_id: user_id) }
  scope :by_id, ->(doc_id) { where(id: doc_id) }
  scope :by_tag_ids, ->(ids) { joins(:tags).where('tags.id': ids) }
  scope :by_group_id, ->(token) {
    where('MATCH(group_id) AGAINST(? IN BOOLEAN MODE)', "#{token}*")
  }
  scope :by_token, ->(token) {
    where('MATCH(group_id) AGAINST(? IN BOOLEAN MODE)', token)
  }
  scope :by_title, ->(title) {
    # where('MATCH(title) AGAINST(? IN BOOLEAN MODE)', "#{title}*")
      # .order('title ASC')
    where('title LIKE ?', "%#{title}%").order('title ASC')
  }
  scope :with_live_files, ->(bln_live_file) {
    query = '(SELECT COUNT(*) FROM docs_editor_live_files '
    query += 'WHERE docs_editor_live_files.doc_id = docs.id)'
    query += bln_live_file ? ' > 0' : ' = 0'
    where(query)
  }

  def remove
    tracking_links.destroy_all
    docs_elements.destroy_all
    docs_editor_live_files.destroy_all
    docs_engagement_pages.delete_all
    docs_files.destroy_all
    destroy
  end

  def count_active_files
    Docs::File.by_doc(id).active.size + Docs::File.by_doc(id).inactive.size + Docs::File.by_doc(id).offline.size
  end

  def count_live_files
    Docs::File.by_doc(id).active.with_live_files.size
  end

  def count_live_files_by_lang
    Docs::File.by_doc(id).active.with_live_files.group(:language).size
  end

  # stats

  def get_engagement_pages
    pages = {}
    docs_engagement_pages.each do |page|
      pages[page.page] = true
    end
    pages
  end

  def get_optins
    Statistics.get_optins(stats_condition)
  end

  def get_viewers
    Statistics.get_viewers(stats_condition)
  end  

  def get_pages_viewed(as = 'percent')
    values = Statistics.get_percent_viewed(id, :doc_id)
    docs_file = docs_files.first

    case as
    when 'percent'
      values[:pages] > 0 ? (Float(values[:pages]) / (values[:sessions] * docs_file.num_pages)) * 100 : 0
    when 'number'
      values[:pages] > 0 ? (Float(values[:pages]) / (values[:sessions])).round : 0
    end
  end

  def get_secs_viewed(as = 'avg')
    values = Statistics.get_secs_viewed(id, :doc_id, stats_condition(:session_pages))

    if as == 'avg'
      # values[:secs] > 0 ? (Float(values[:secs]) / values[:sessions]) : 0
      values[:secs] > 0 ? (Float(values[:secs]) / self.get_viewers) : 0
    else
      values[:secs]
    end
  end

  def get_popular_pages
    Statistics.get_popular_pages(id, :doc_id, stats_condition(:session_pages))
  end

  def get_pages_by_most_time_spent
    Statistics.get_pages_by_time_spent(id, :doc_id, stats_condition(:session_pages))
  end

  def get_exit_pages(popular = true)
    Statistics.get_exit_pages(id, 'session_pages.doc_id', stats_condition(:session_pages), popular)
  end

  def get_page_secs_viewed
    values = Statistics.get_page_secs_viewed(stats_condition, 'session_pages.page')

    values[:secs] > 0 ? (Float(values[:secs]) / values[:pages]) : 0
  end

  def get_returning_viewers
    Statistics.get_returning_viewers(stats_condition)
  end

  def get_engagement(as = 'percent')
    # engagement = Statistics.get_engagement(:doc_id, stats_condition(:session_pages),docs_files.first.num_pages)
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
        condition = "#{stats_condition} AND sessions.#{field} = '#{val[field.to_sym]}'"
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
    page_info = Statistics.get_secs_viewed_by_page(stats_condition(:session_pages))
    page_info.each_with_index do |page, idx|
      page_info[idx][:total_secs] = page[:secs]
      page_info[idx][:secs] = page[:secs] > 0 ? (Float(page[:secs]) / page[:views]) : 0
    end

    page_info.sort_by! { |hsh| hsh[sort_val.to_sym] }

    page_info.reverse! if sort_order == 'desc'
  end

  def get_page_viewers
    Statistics.get_page_viewers(stats_condition)
  end

  def get_elements_click
    Statistics.get_elements_click(stats_condition(:session_pages))
  end


  def filter_viewers(threshold)
    StatisticsFilter.get_viewers(stats_condition, threshold)
  end

  def filter_secs_viewed(as = 'avg', threshold)
    values = StatisticsFilter.get_secs_viewed(id, :doc_id, stats_condition(:session_pages), threshold)

    if as == 'avg'
      values[:secs] > 0 ? (Float(values[:secs]) / values[:sessions]) : 0
    else
      values[:secs]
    end
  end

  def filter_pages_viewed(as = 'percent', threshold)
    values = StatisticsFilter.get_percent_viewed(id, :doc_id, threshold)
    docs_file = docs_files.first

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

  def filter_optins(threshold)
    StatisticsFilter.get_optins(stats_condition, threshold)
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

  def stats_condition(table_name = :session_tracking_links)
    "#{table_name}.doc_id = #{id}"
  end

  def remove_dir
    rm_dir = Rails.root.join('public', 'storage', group_id).to_s
    puts "rm_dir: #{rm_dir}"
    FileUtils.rm_r(rm_dir) if File.exist?(rm_dir)
  end

  def stat_type
    {
        type: 'doc',
        id: id,
        id_field_name: 'doc_id',
        num_pages: docs_files.first.nil? ? 0 : docs_files.first.num_pages
    }
  end
end
