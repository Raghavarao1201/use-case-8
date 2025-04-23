import boto3
import os
from io import BytesIO
from PIL import Image

s3 = boto3.client('s3')
processed_bucket_name = os.environ.get('PROCESSED_BUCKET_NAME')

def resize_image(image_data, max_width=512, max_height=512):
    """Resizes an image while maintaining aspect ratio."""
    img = Image.open(BytesIO(image_data))
    img.draft(img.mode, (max_width, max_height))  # Efficiently load only necessary data
    size = (max_width, max_height)
    img.thumbnail(size)  # Resize in-place, maintaining aspect ratio
    buffer = BytesIO()
    img.save(buffer, 'JPEG')  # Save as JPEG for processed images
    buffer.seek(0)
    return buffer

def detect_objects(image_data):
    """
    Placeholder for object detection logic.
    In a real-world scenario, you would integrate with services like
    Amazon Rekognition here. For this example, it simply returns a message.
    """

    return "Object detection processing complete (placeholder)."

def lambda_handler(event, context):
    """
    Handles S3 object creation events, processes the image,
    and stores the processed image in another S3 bucket.
    """
    for record in event['Records']:
        bucket = record['s3']['bucket']['name']
        key = record['s3']['object']['key']

        print(f"Processing image: {key} from bucket: {bucket}")

        try:
            response = s3.get_object(Bucket=bucket, Key=key)
            image_data = response['Body'].read()

            # Resize the image
            resized_image_buffer = resize_image(image_data)
            resized_image_key = f"resized/{os.path.splitext(key)[0]}_resized.jpg"
            s3.upload_fileobj(resized_image_buffer, processed_bucket_name, resized_image_key)
            print(f"Resized image uploaded to: s3://{processed_bucket_name}/{resized_image_key}")

            # Perform object detection (placeholder)
            detection_result = detect_objects(image_data)
            detection_result_key = f"detections/{os.path.splitext(key)[0]}_detections.txt"
            s3.put_object(Body=detection_result.encode('utf-8'), Bucket=processed_bucket_name, Key=detection_result_key)
            print(f"Object detection result uploaded to: s3://{processed_bucket_name}/{detection_result_key}")

            print(f"Successfully processed: {key}")

        except Exception as e:
            print(f"Error processing {key}: {e}")
            raise e

    return {
        'statusCode': 200,
        'body': 'Images processed successfully!'
    }

if __name__ == "__main__":
    # Example invocation for local testing
    test_event = {
        'Records': [
            {
                's3': {
                    'bucket': {'name': 'your-source-bucket-name'},  # Replace with your source bucket name
                    'object': {'key': 'uploads/test_image.jpg'}      # Replace with a test image key
                }
            }
        ]
    }
    lambda_handler(test_event, None)