import { photoAccessHelper } from '@kit.MediaLibraryKit';

export class GalleryPhotoPicker {
  async selectImageUris(maxSelectNumber: number = 9): Promise<string[]> {
    try {
      let options = new photoAccessHelper.PhotoSelectOptions();
      options.MIMEType = photoAccessHelper.PhotoViewMIMETypes.IMAGE_TYPE;
      options.maxSelectNumber = maxSelectNumber;
      options.isOriginalSupported = true;
      let picker = new photoAccessHelper.PhotoViewPicker();
      let result = await picker.select(options);
      return result.photoUris;
    } catch (e) {
      let err = e as Error;
      throw err;
    }
  }
}
