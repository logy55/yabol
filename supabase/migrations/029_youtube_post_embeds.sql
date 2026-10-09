-- Apply after 028. Accept only a YouTube video ID, never iframe HTML or external URLs.
begin;
create or replace function private.rich_document_valid(p_doc jsonb,p_image_count integer) returns boolean
language plpgsql immutable set search_path='' as $$
declare item record; node jsonb; attrs jsonb; kind text; allowed text[]; child_types text[];
  mark jsonb; total_nodes integer:=0; total_text integer:=0;
begin
  if p_doc is null then return true; end if;
  if jsonb_typeof(p_doc)<>'object' or p_doc->>'type'<>'doc' or char_length(p_doc::text)>200000 then return false; end if;
  for item in
    with recursive walk(node,parent,depth) as (
      select p_doc,'ROOT'::text,0
      union all
      select child.value,w.node->>'type',w.depth+1 from walk w
      cross join lateral jsonb_array_elements(case when jsonb_typeof(w.node->'content')='array' then w.node->'content' else '[]'::jsonb end) child
      where w.depth<=10
    ) select * from walk
  loop
    node:=item.node; kind:=node->>'type'; total_nodes:=total_nodes+1;
    if total_nodes>2000 or item.depth>10 or jsonb_typeof(node)<>'object' or kind is null then return false; end if;
    child_types:=case item.parent
      when 'ROOT' then array['doc']
      when 'doc' then array['paragraph','heading','blockquote','bulletList','orderedList','codeBlock','horizontalRule','table','image','youtube']
      when 'paragraph' then array['text','hardBreak','yabolticon']
      when 'heading' then array['text','hardBreak','yabolticon']
      when 'codeBlock' then array['text']
      when 'blockquote' then array['paragraph','heading','blockquote','bulletList','orderedList','codeBlock','horizontalRule','table','image','youtube']
      when 'listItem' then array['paragraph','heading','blockquote','bulletList','orderedList','codeBlock','horizontalRule','table','image','youtube']
      when 'bulletList' then array['listItem']
      when 'orderedList' then array['listItem']
      when 'table' then array['tableRow']
      when 'tableRow' then array['tableCell','tableHeader']
      when 'tableCell' then array['paragraph','heading','blockquote','bulletList','orderedList','codeBlock','horizontalRule','image','youtube']
      when 'tableHeader' then array['paragraph','heading','blockquote','bulletList','orderedList','codeBlock','horizontalRule','image','youtube']
      else array[]::text[] end;
    if not(kind=any(child_types)) then return false; end if;
    allowed:=case
      when kind='text' then array['type','text','marks']
      when kind in ('image','yabolticon','youtube') then array['type','attrs']
      when kind in ('hardBreak','horizontalRule') then array['type']
      when kind in ('heading','orderedList','tableCell','tableHeader') then array['type','attrs','content']
      else array['type','content'] end;
    if exists(select 1 from jsonb_object_keys(node) key where not(key=any(allowed))) then return false; end if;
    if kind='text' then
      if jsonb_typeof(node->'text') is distinct from 'string' then return false; end if;
      total_text:=total_text+char_length(node->>'text'); if total_text>10000 then return false; end if;
      if node ? 'marks' then
        if jsonb_typeof(node->'marks')<>'array' or jsonb_array_length(node->'marks')>5 then return false; end if;
        for mark in select value from jsonb_array_elements(node->'marks') loop
          if jsonb_typeof(mark)<>'object' or (mark-'type')<>'{}'::jsonb or (mark->>'type') is null
            or not(mark->>'type'=any(array['bold','italic','underline','strike','code'])) then return false; end if;
        end loop;
      end if;
    elsif kind not in ('image','yabolticon','youtube','hardBreak','horizontalRule') then
      if jsonb_typeof(node->'content') is distinct from 'array' then return false; end if;
      if kind='table' and jsonb_array_length(node->'content') not between 1 and 20 then return false; end if;
      if kind='tableRow' and jsonb_array_length(node->'content') not between 1 and 10 then return false; end if;
    end if;
    if kind in ('image','yabolticon','youtube','heading','orderedList','tableCell','tableHeader') then
      attrs:=node->'attrs'; if jsonb_typeof(attrs) is distinct from 'object' then return false; end if;
      if kind='image' then
        if (attrs-array['index','alt'])<>'{}'::jsonb or jsonb_typeof(attrs->'index') is distinct from 'number'
          or coalesce(attrs->>'index','') !~ '^[0-4]$' or (attrs->>'index')::integer>=p_image_count
          or jsonb_typeof(attrs->'alt') is distinct from 'string' or char_length(attrs->>'alt')>200 then return false; end if;
      elsif kind='youtube' then
        if (attrs-'videoId')<>'{}'::jsonb or jsonb_typeof(attrs->'videoId') is distinct from 'string'
          or coalesce(attrs->>'videoId','') !~ '^[A-Za-z0-9_-]{11}$' then return false; end if;
      elsif kind='yabolticon' then
        if (attrs-'id')<>'{}'::jsonb or (attrs->>'id') is null
          or not(attrs->>'id'=any(array['hello','laugh','cheer','homerun','cry','angry','clap','thanks'])) then return false; end if;
      elsif kind='heading' then
        if (attrs-'level')<>'{}'::jsonb or jsonb_typeof(attrs->'level') is distinct from 'number' or coalesce(attrs->>'level','') !~ '^[23]$' then return false; end if;
      elsif kind='orderedList' then
        if (attrs-'start')<>'{}'::jsonb or jsonb_typeof(attrs->'start') is distinct from 'number'
          or coalesce(attrs->>'start','') !~ '^[1-9][0-9]{0,2}$' then return false; end if;
      else
        if (attrs-array['colspan','rowspan'])<>'{}'::jsonb or jsonb_typeof(attrs->'colspan') is distinct from 'number'
          or jsonb_typeof(attrs->'rowspan') is distinct from 'number' or coalesce(attrs->>'colspan','') !~ '^[1-9][0-9]?$'
          or coalesce(attrs->>'rowspan','') !~ '^[1-9][0-9]?$'
          or (attrs->>'colspan')::integer>10 or (attrs->>'rowspan')::integer>20 then return false; end if;
      end if;
    end if;
  end loop;
  return true;
exception when others then return false;
end; $$;
revoke all on function private.rich_document_valid(jsonb,integer) from public,anon,authenticated;

commit;
