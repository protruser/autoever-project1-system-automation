import json

def generate_json(full_data):
    return json.dumps(full_data, ensure_ascii=False, indent=2, default=str)
