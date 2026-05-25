DO $$
BEGIN
   IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'fk_data_source_control_source_system') THEN
      ALTER TABLE auth.data_source_control
          ADD CONSTRAINT fk_data_source_control_source_system
          FOREIGN KEY (source_system_id)
          REFERENCES meta.source_system(source_system_id)
          ON UPDATE RESTRICT
          ON DELETE CASCADE;
   END IF;
END $$;