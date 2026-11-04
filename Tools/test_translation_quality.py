import os
import unittest
from pathlib import Path
from unittest.mock import patch
from translation_quality import translation_issues
import repair_word_timing_catalog as config

class TranslationQualityTests(unittest.TestCase):
    def test_missing_object_is_held_instead_of_publishing_reversed_meaning(self):
        line={"translation":"I'll put a sponge on it.","tokens":[{"surface":"detergent","pos":"noun","definitions":["detergent; cleaner"]},{"surface":"sponge","pos":"noun","definitions":["sponge"]}]}
        self.assertEqual(len(translation_issues([line])),1)
        line["translation"]="Put detergent on the sponge."
        self.assertEqual(translation_issues([line]),[])

    def test_workflow_configuration_does_not_require_a_private_local_plist(self):
        with patch.object(config,"ROOT",Path("/nonexistent")), patch.dict(os.environ,{"SUPABASE_URL":"https://example.test/","SUPABASE_ANON_KEY":"test"}):
            self.assertEqual(config.configuration(),("https://example.test","test"))

if __name__ == "__main__":unittest.main()
