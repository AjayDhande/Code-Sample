#
module StatsConcern
  extend ActiveSupport::Concern

  # condition -> SQL condition
  # stats_for -> { type: 'tracking_link', id: tl.id, id_field_name: 'tracking_link_id', total_pages: int }
  # threshold -> int
  def engagement(stats_for, condition = '1', threshold = 10)
    engagement_sessions = execute_statement generate_engagement_query("COUNT(DISTINCT(session_pages.session_id)) AS sessions, session_pages.#{stats_for[:id_field_name]}", condition, threshold)
    engagement_pages = execute_statement generate_engagement_query("COUNT(DISTINCT(session_pages.page)) AS pages, session_pages.#{stats_for[:id_field_name]}", condition, threshold)

    total_sessions = execute_statement generate_engagement_query('COUNT(DISTINCT(session_id)) AS cnt', condition, threshold)
    total_pages = stats_for[:num_pages]
    return 0 if total_pages.nil?
    (1.0 * engagement_sessions[0]['sessions'] * engagement_pages[0]['pages']) / (total_sessions[0]['cnt'] * total_pages)
  end

  def engagement_score(score, as)
    if as == 'percent'
      score = score > 0 ? score * 100 : 0
    elsif as =='number'
      score = score > 0 ? score.round : 0
    end
    score
  end

  # for one session
  # condition -> SQL condition
  # stats_for -> { type: 'tracking_link', id: tl.id, id_field_name: 'tracking_link_id' }
  # threshold -> int
  def exit_page(stats_for, condition = '1')
    query = "SELECT session_pages.#{stats_for[:id_field_name]}, "
    query += ' session_pages.session_id, session_pages.page '
    query += ' FROM session_pages '
    query += " WHERE #{condition} AND session_pages.id = "
    query += ' (SELECT MAX(sp.id) AS latest FROM session_pages sp'
    query += ' WHERE sp.session_id = session_pages.session_id '
    query += ' AND sp.tracking_link_id = session_pages.tracking_link_id'
    query += " AND #{condition} )"
    query += " GROUP BY session_pages.session_id"
    query += ' ORDER BY session_pages.created_at DESC'
    execute_statement query
  end

  def exit_pages(stats_for, condition = '1', popular)
    pages = exit_page(stats_for, condition)
    total_exit_pages = compute_total_exit_pages(pages, stats_for[:id_field_name])

    ret_val = { pages: ['-'], views: 0 }
    unless total_exit_pages[id].nil?
      if popular
        ret_val = get_popular_exit_pages(total_exit_pages, stats_for[:id])
      else
        ret_val = total_exit_pages[id]
      end
    end
    ret_val
  end

  private

  def generate_engagement_query(fields, condition, threshold)
    query = "SELECT #{fields} FROM session_pages "
    query += 'INNER JOIN docs ON session_pages.doc_id = docs.id '
    query += 'INNER JOIN docs_engagement_pages ON docs_engagement_pages.doc_id = session_pages.doc_id '
    query += 'AND docs_engagement_pages.page = session_pages.page '
    query += "WHERE #{condition} AND seconds_on_page >= #{threshold}"
  end

  def compute_total_exit_pages(pages, fld_name)
    total_exit_pages = {}
    return {} if pages.nil?
    pages.each do |page|
      if total_exit_pages[page[fld_name]].nil?
        total_exit_pages[page[fld_name]] = {}
      end
      if total_exit_pages[page[fld_name]][page['page']].nil?
        total_exit_pages[page[fld_name]][page['page']] = 1
      else
        total_exit_pages[page[fld_name]][page['page']] = total_exit_pages[page[fld_name]][page['page']] + 1
      end
    end
    total_exit_pages
  end

  def get_popular_exit_pages(total_exit_pages, id)
    ret_val = { pages: ['-'], views: 0 }

    total_exit_pages[id].each do |page, val|
      if val == ret_val[:views]
        ret_val[:pages].push page
      elsif val > ret_val[:views]
        ret_val[:pages] = [page]
        ret_val[:views] = val
      end
    end
    ret_val
  end
end

# engagement
# t = TrackingLink.find(136);nil
# s = Session.find 1133;nil
# parent = {type: 'tracking_link', id: t.id, id_field_name: 'tracking_link_id', num_pages: t.doc.docs_files.first.num_pages};nil
# s.engagement(parent, 'session_pages.session_id = 1133')
# t.engagement(parent, 'session_pages.tracking_link_id = 136')
# t.get_engagement('number')
# t.get_secs_viewed('total')
#
# exit page
# s = Session.find 1133;nil
# stats_for = { type: 'session', id: s.id, id_field_name: 'session_id' }
# condition = "session_pages.session_id = #{s.id}"
# s.exit_page(stats_for, condition)
# t = TrackingLink.find(136);nil
# stats_for = { type: 'tracking_link', id: t.id, id_field_name: 'tracking_link_id' }
# condition = "session_pages.tracking_link_id = #{t.id}"
# t.exit_page(stats_for, condition)
# t.get_secs_viewed('total')
#
# d = Doc.find(114);nil
# stats_for = { type: 'doc', id: d.id, id_field_name: 'doc_id' }
# condition = "session_pages.doc_id = #{d.id}"
# d.exit_page(stats_for, condition)