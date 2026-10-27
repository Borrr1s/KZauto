-- WARNING: This schema is for context only and is not meant to be run.
-- Table order and constraints may not be valid for execution.

CREATE TABLE public.sites (
  id uuid NOT NULL DEFAULT gen_random_uuid(),
  name text NOT NULL UNIQUE,
  created_at timestamp with time zone DEFAULT now(),
  CONSTRAINT sites_pkey PRIMARY KEY (id)
);
CREATE TABLE public.profiles (
  id uuid NOT NULL,
  email text,
  name text,
  role text NOT NULL DEFAULT 'mechanic'::text CHECK (role = ANY (ARRAY['boss'::text, 'senior'::text, 'mechanic'::text])),
  status text NOT NULL DEFAULT 'pending'::text CHECK (status = ANY (ARRAY['pending'::text, 'active'::text, 'blocked'::text])),
  site_id uuid,
  created_at timestamp with time zone DEFAULT now(),
  CONSTRAINT profiles_pkey PRIMARY KEY (id),
  CONSTRAINT profiles_id_fkey FOREIGN KEY (id) REFERENCES auth.users(id),
  CONSTRAINT profiles_site_id_fkey FOREIGN KEY (site_id) REFERENCES public.sites(id)
);
CREATE TABLE public.cars (
  id uuid NOT NULL DEFAULT gen_random_uuid(),
  name text NOT NULL,
  plate text DEFAULT ''::text,
  site_id uuid NOT NULL,
  oil_date date,
  created_at timestamp with time zone DEFAULT now(),
  CONSTRAINT cars_pkey PRIMARY KEY (id),
  CONSTRAINT cars_site_id_fkey FOREIGN KEY (site_id) REFERENCES public.sites(id)
);
CREATE TABLE public.tasks (
  id uuid NOT NULL DEFAULT gen_random_uuid(),
  car_id uuid NOT NULL,
  kind text NOT NULL CHECK (kind = ANY (ARRAY['repair'::text, 'task'::text])),
  text text NOT NULL,
  assignee uuid,
  done boolean NOT NULL DEFAULT false,
  created_by uuid,
  done_by uuid,
  created_at timestamp with time zone DEFAULT now(),
  done_at timestamp with time zone,
  CONSTRAINT tasks_pkey PRIMARY KEY (id),
  CONSTRAINT tasks_car_id_fkey FOREIGN KEY (car_id) REFERENCES public.cars(id),
  CONSTRAINT tasks_assignee_fkey FOREIGN KEY (assignee) REFERENCES public.profiles(id),
  CONSTRAINT tasks_created_by_fkey FOREIGN KEY (created_by) REFERENCES public.profiles(id),
  CONSTRAINT tasks_done_by_fkey FOREIGN KEY (done_by) REFERENCES public.profiles(id)
);
CREATE TABLE public.transfers (
  id uuid NOT NULL DEFAULT gen_random_uuid(),
  car_id uuid NOT NULL,
  from_site uuid,
  to_site uuid,
  requested_by uuid,
  status text NOT NULL DEFAULT 'pending'::text CHECK (status = ANY (ARRAY['pending'::text, 'approved'::text, 'rejected'::text])),
  decided_by uuid,
  created_at timestamp with time zone DEFAULT now(),
  CONSTRAINT transfers_pkey PRIMARY KEY (id),
  CONSTRAINT transfers_car_id_fkey FOREIGN KEY (car_id) REFERENCES public.cars(id),
  CONSTRAINT transfers_from_site_fkey FOREIGN KEY (from_site) REFERENCES public.sites(id),
  CONSTRAINT transfers_to_site_fkey FOREIGN KEY (to_site) REFERENCES public.sites(id),
  CONSTRAINT transfers_requested_by_fkey FOREIGN KEY (requested_by) REFERENCES public.profiles(id),
  CONSTRAINT transfers_decided_by_fkey FOREIGN KEY (decided_by) REFERENCES public.profiles(id)
);
CREATE TABLE public.log (
  id bigint GENERATED ALWAYS AS IDENTITY NOT NULL,
  car_id uuid,
  car_name text,
  actor uuid,
  actor_name text,
  action text,
  details text,
  at timestamp with time zone DEFAULT now(),
  CONSTRAINT log_pkey PRIMARY KEY (id)
);
