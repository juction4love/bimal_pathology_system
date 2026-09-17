SELECT code, count(*) FROM public.tests GROUP BY code HAVING count(*) > 1;
