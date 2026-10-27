BEGIN;

ALTER TABLE public.cars
  ADD COLUMN IF NOT EXISTS manual_ready boolean NOT NULL DEFAULT false;

CREATE OR REPLACE FUNCTION public.set_car_ready(p_car uuid, p_ready boolean)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  c public.cars;
BEGIN
  IF p_ready IS NULL THEN
    RAISE EXCEPTION 'Не указан статус готовности';
  END IF;

  PERFORM public._need(ARRAY['boss', 'senior']);
  PERFORM public._car(p_car);

  SELECT * INTO c
  FROM public.cars
  WHERE id = p_car
  FOR UPDATE;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Машина не найдена';
  END IF;

  PERFORM public._car(p_car);

  IF p_ready AND EXISTS (
    SELECT 1
    FROM public.tasks
    WHERE car_id = p_car
      AND NOT done
      AND kind = 'repair'
  ) THEN
    RAISE EXCEPTION 'Нельзя отметить машину готовой: есть незавершённый ремонт';
  END IF;

  IF p_ready AND NOT EXISTS (
    SELECT 1
    FROM public.tasks
    WHERE car_id = p_car
      AND NOT done
      AND kind = 'task'
  ) THEN
    RAISE EXCEPTION 'Нет незавершённых задач для ручного перевода в готовность';
  END IF;

  UPDATE public.cars
  SET manual_ready = p_ready
  WHERE id = p_car;

  PERFORM public._log(
    c.id,
    c.name,
    'car_ready',
    CASE
      WHEN p_ready THEN 'Машина вручную отмечена готовой'
      ELSE 'Ручная готовность снята'
    END
  );
END;
$$;

REVOKE ALL ON FUNCTION public.set_car_ready(uuid, boolean) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.set_car_ready(uuid, boolean) TO authenticated;

CREATE OR REPLACE FUNCTION public.reset_car_manual_ready_on_task()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  c public.cars;
BEGIN
  UPDATE public.cars
  SET manual_ready = false
  WHERE id = NEW.car_id
    AND manual_ready
  RETURNING * INTO c;

  IF FOUND THEN
    PERFORM public._log(
      c.id,
      c.name,
      'car_ready_reset',
      'Новая задача сняла ручную готовность'
    );
  END IF;

  RETURN NEW;
END;
$$;

REVOKE ALL ON FUNCTION public.reset_car_manual_ready_on_task()
  FROM PUBLIC, anon, authenticated;

DROP TRIGGER IF EXISTS tasks_reset_car_manual_ready ON public.tasks;
CREATE TRIGGER tasks_reset_car_manual_ready
  AFTER INSERT ON public.tasks
  FOR EACH ROW
  EXECUTE FUNCTION public.reset_car_manual_ready_on_task();

COMMIT;
