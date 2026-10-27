ALTER TABLE public.profiles
  ADD COLUMN IF NOT EXISTS all_sites boolean NOT NULL DEFAULT false;

CREATE OR REPLACE FUNCTION public.cur_all_sites()
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $$
  SELECT COALESCE((
    SELECT p.all_sites
    FROM public.profiles AS p
    WHERE p.id = (SELECT auth.uid())
      AND p.status = 'active'
  ), false);
$$;

REVOKE ALL ON FUNCTION public.cur_all_sites() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.cur_all_sites() TO authenticated;

DROP POLICY IF EXISTS c_sel ON public.cars;
CREATE POLICY c_sel ON public.cars
  FOR SELECT TO authenticated
  USING (
    public.cur_role() = 'boss'
    OR (
      public.cur_role() IN ('senior', 'mechanic')
      AND (
        site_id = public.cur_site()
        OR public.cur_all_sites()
      )
    )
  );

DROP POLICY IF EXISTS tr_sel ON public.transfers;
CREATE POLICY tr_sel ON public.transfers
  FOR SELECT TO authenticated
  USING (
    public.cur_role() = 'boss'
    OR (
      public.cur_role() IS NOT NULL
      AND (
        from_site = public.cur_site()
        OR to_site = public.cur_site()
        OR public.cur_all_sites()
      )
    )
  );

CREATE OR REPLACE FUNCTION public._car(p_car uuid)
RETURNS public.cars
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  c public.cars;
  r text;
BEGIN
  SELECT * INTO c FROM public.cars WHERE id = p_car;
  IF c.id IS NULL THEN
    RAISE EXCEPTION 'Машина не найдена';
  END IF;

  r := public.cur_role();
  IF r IS NULL THEN
    RAISE EXCEPTION 'Нет доступа';
  END IF;
  IF r <> 'boss'
    AND c.site_id IS DISTINCT FROM public.cur_site()
    AND NOT public.cur_all_sites()
  THEN
    RAISE EXCEPTION 'Нет доступа к этой площадке';
  END IF;

  RETURN c;
END;
$$;

CREATE OR REPLACE FUNCTION public.add_car(
  p_name text,
  p_plate text,
  p_site uuid,
  p_oil date DEFAULT NULL
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  i uuid;
BEGIN
  PERFORM public._need(ARRAY['boss', 'senior']);
  IF public.cur_role() = 'senior'
    AND p_site IS DISTINCT FROM public.cur_site()
    AND NOT public.cur_all_sites()
  THEN
    RAISE EXCEPTION 'Ст. механик добавляет машины только на свою площадку';
  END IF;
  IF COALESCE(trim(p_name), '') = '' THEN
    RAISE EXCEPTION 'Пустое название';
  END IF;

  INSERT INTO public.cars(name, plate, site_id, oil_date)
  VALUES (trim(p_name), COALESCE(trim(p_plate), ''), p_site, p_oil)
  RETURNING id INTO i;

  PERFORM public._log(
    i,
    trim(p_name),
    'car_add',
    'Машина добавлена на площадку «'
      || (SELECT s.name FROM public.sites AS s WHERE s.id = p_site)
      || '»'
  );
END;
$$;

CREATE OR REPLACE FUNCTION public.add_task(
  p_car uuid,
  p_kind text,
  p_text text,
  p_assignee uuid DEFAULT NULL
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  c public.cars;
BEGIN
  c := public._car(p_car);

  IF p_kind NOT IN ('repair', 'task') OR COALESCE(trim(p_text), '') = '' THEN
    RAISE EXCEPTION 'Некорректная задача';
  END IF;
  IF public.cur_role() = 'mechanic'
    AND p_assignee IS NOT NULL
    AND p_assignee <> (SELECT auth.uid())
  THEN
    RAISE EXCEPTION 'Механик может назначить задачу только себе';
  END IF;
  IF p_assignee IS NOT NULL AND NOT EXISTS (
    SELECT 1
    FROM public.profiles AS p
    WHERE p.id = p_assignee
      AND p.status = 'active'
      AND (p.site_id = c.site_id OR p.role = 'boss' OR p.all_sites)
  ) THEN
    RAISE EXCEPTION 'Исполнитель не с этой площадки';
  END IF;

  INSERT INTO public.tasks(car_id, kind, text, assignee, created_by)
  VALUES (p_car, p_kind, trim(p_text), p_assignee, (SELECT auth.uid()));

  PERFORM public._log(
    p_car,
    c.name,
    'task_add',
    (CASE p_kind WHEN 'repair' THEN 'Ремонт' ELSE 'Задача' END)
      || ': ' || trim(p_text)
      || (CASE
        WHEN p_assignee IS NULL THEN ' (не назначена)'
        ELSE ' → ' || public._pname(p_assignee)
      END)
  );
END;
$$;

CREATE OR REPLACE FUNCTION public.assign_task(p_task uuid, p_assignee uuid)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  t public.tasks;
  c public.cars;
BEGIN
  PERFORM public._need(ARRAY['boss', 'senior']);

  SELECT * INTO t FROM public.tasks WHERE id = p_task;
  IF t.id IS NULL THEN
    RAISE EXCEPTION 'Задача не найдена';
  END IF;
  c := public._car(t.car_id);
  IF t.done THEN
    RAISE EXCEPTION 'Задача уже выполнена';
  END IF;
  IF p_assignee IS NOT NULL AND NOT EXISTS (
    SELECT 1
    FROM public.profiles AS p
    WHERE p.id = p_assignee
      AND p.status = 'active'
      AND (p.site_id = c.site_id OR p.role = 'boss' OR p.all_sites)
  ) THEN
    RAISE EXCEPTION 'Исполнитель не с этой площадки';
  END IF;

  UPDATE public.tasks SET assignee = p_assignee WHERE id = p_task;

  PERFORM public._log(
    c.id,
    c.name,
    'task_assign',
    'Задача «' || t.text || '»: '
      || CASE
        WHEN p_assignee IS NULL THEN 'снята с исполнителя'
        ELSE 'назначена → ' || public._pname(p_assignee)
      END
  );
END;
$$;

CREATE OR REPLACE FUNCTION public.set_profile_scope(
  p_id uuid,
  p_role text,
  p_status text,
  p_site uuid,
  p_all_sites boolean
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_role text;
  v_status text;
BEGIN
  PERFORM public._need(ARRAY['boss']);

  SELECT p.role, p.status
  INTO v_role, v_status
  FROM public.profiles AS p
  WHERE p.id = p_id
  FOR UPDATE;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Профиль не найден';
  END IF;

  IF p_id = (SELECT auth.uid())
    AND (p_role IS DISTINCT FROM v_role OR p_status IS DISTINCT FROM v_status)
  THEN
    RAISE EXCEPTION 'Нельзя менять свою роль или статус';
  END IF;

  UPDATE public.profiles
  SET role = p_role,
      status = p_status,
      site_id = CASE WHEN COALESCE(p_all_sites, false) THEN NULL ELSE p_site END,
      all_sites = COALESCE(p_all_sites, false)
  WHERE id = p_id;
END;
$$;

REVOKE ALL ON FUNCTION public.set_profile_scope(uuid, text, text, uuid, boolean)
  FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.set_profile_scope(uuid, text, text, uuid, boolean)
  TO authenticated;

CREATE OR REPLACE FUNCTION public.delete_profile(p_id uuid)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_role text;
  v_status text;
  v_active_bosses bigint;
BEGIN
  PERFORM public._need(ARRAY['boss']);

  IF p_id IS NULL THEN
    RAISE EXCEPTION 'Не указан профиль';
  END IF;
  IF p_id = (SELECT auth.uid()) THEN
    RAISE EXCEPTION 'Нельзя удалить собственный профиль';
  END IF;

  PERFORM pg_advisory_xact_lock(642018237);

  SELECT p.role, p.status
  INTO v_role, v_status
  FROM public.profiles AS p
  WHERE p.id = p_id
  FOR UPDATE;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Профиль не найден';
  END IF;

  IF v_role = 'boss' AND v_status = 'active' THEN
    SELECT count(*)
    INTO v_active_bosses
    FROM public.profiles AS p
    WHERE p.role = 'boss'
      AND p.status = 'active'
      AND p.id <> p_id;
    IF v_active_bosses = 0 THEN
      RAISE EXCEPTION 'Нельзя удалить последнего активного босса';
    END IF;
  END IF;

  DELETE FROM auth.users AS u WHERE u.id = p_id;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Аккаунт не найден';
  END IF;
END;
$$;

REVOKE ALL ON FUNCTION public.delete_profile(uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.delete_profile(uuid) TO authenticated;
