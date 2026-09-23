-- HUI ZUAN V3.1 安全更換館型
-- 請在 Supabase SQL Editor 執行一次。
-- 核心：整個換館動作在同一個 transaction/function 內完成；任何錯誤都會整筆回滾。

create or replace function public.change_host_gallery_size(
  p_gallery_id bigint,
  p_new_gallery_size integer
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_old_size integer;
  v_template_gallery_id bigint;
begin
  if p_new_gallery_size not in (12,20,24,28) then
    raise exception '不支援的館型：%', p_new_gallery_size;
  end if;

  select gallery_size into v_old_size
  from public.host_galleries
  where id = p_gallery_id
  for update;

  if v_old_size is null then
    raise exception '找不到展館 id=%', p_gallery_id;
  end if;
  if v_old_size = p_new_gallery_size then
    return;
  end if;

  -- 從資料庫現有同館型展館複製禮物模板。
  select hg.id into v_template_gallery_id
  from public.host_galleries hg
  where hg.gallery_size = p_new_gallery_size
    and hg.id <> p_gallery_id
    and exists (select 1 from public.gallery_items gi where gi.gallery_id = hg.id)
  order by hg.id desc
  limit 1;

  if v_template_gallery_id is null then
    raise exception '資料庫目前沒有可用的 % 館模板，請先建立任一 % 館', p_new_gallery_size, p_new_gallery_size;
  end if;

  -- 只清除「這一館」舊禮物所屬的點亮紀錄。
  delete from public.light_records
  where gallery_item_id in (
    select id from public.gallery_items where gallery_id = p_gallery_id
  );

  delete from public.gallery_items where gallery_id = p_gallery_id;

  update public.host_galleries
  set gallery_size = p_new_gallery_size,
      is_full = false,
      full_at = null
  where id = p_gallery_id;

  insert into public.gallery_items
    (gallery_id,item_name,image_url,target_count,current_count,sort_order,completed_at)
  select
    p_gallery_id,item_name,image_url,target_count,0,sort_order,null
  from public.gallery_items
  where gallery_id = v_template_gallery_id
  order by sort_order;

  if not exists (select 1 from public.gallery_items where gallery_id = p_gallery_id) then
    raise exception '新館禮物建立失敗，已自動回滾';
  end if;
end;
$$;

grant execute on function public.change_host_gallery_size(bigint,integer) to anon, authenticated;
