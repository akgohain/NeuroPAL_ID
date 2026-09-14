function rgb = scale_video_projection(app, projection)
%SCALE_VIDEO_PROJECTION Apply the viewer's RGB gains in the source class.
rgb = zeros(size(projection,1),size(projection,2),3,'like',projection);
gains = [app.RSlider.Value app.GSlider.Value app.BSlider.Value];
for c = 1:min(3,size(projection,3))
    rgb(:,:,c) = projection(:,:,c)*gains(c);
end
end
