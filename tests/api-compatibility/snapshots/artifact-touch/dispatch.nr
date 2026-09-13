        // Both exact current classes are required. A custom first setter may mutate
        // the second store, so a mixed pair must retain BOTH original set calls.
        let use_touch = if (::libs::config_class::ARTIFACT_TOUCH_CLASS == 0)
            | (::libs::config_class::LOCATION_TOUCH_CLASS == 0) {
            false
        } else if artifact_storage.target_contract == artifact_location_storage.target_contract {
            false
        } else {
            let artifact_class = ::aztec::oracle::get_contract_instance::get_contract_instance_current_class_id_avm(artifact_storage.target_contract);
            let location_class = ::aztec::oracle::get_contract_instance::get_contract_instance_current_class_id_avm(artifact_location_storage.target_contract);
            if artifact_class.is_some() & location_class.is_some() {
                (artifact_class.unwrap().to_field() == ::libs::config_class::ARTIFACT_TOUCH_CLASS)
                    & (location_class.unwrap().to_field() == ::libs::config_class::LOCATION_TOUCH_CLASS)
            } else { false }
        };
        if use_touch {
            self.call(artifact_storage.touch(artifact, id));
            self.call(artifact_location_storage.touch(location, id));
        } else {
            self.call(artifact_storage.set(id, artifact));
            self.call(artifact_location_storage.set(id, location));
        }
