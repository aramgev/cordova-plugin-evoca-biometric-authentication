package cordova.plugin.biometricauth;

import org.apache.cordova.CordovaPlugin;
import org.apache.cordova.CallbackContext;

import org.apache.cordova.PluginResult;


import com.google.gson.Gson;


import org.json.JSONArray;
import org.json.JSONException;
import org.json.JSONObject;

import android.content.Context;
import android.content.res.Resources;

import android.content.Intent;
import android.os.Bundle;
import android.view.View;
import android.widget.TextView;

import androidx.appcompat.app.AppCompatActivity;
import java.util.ArrayList;
import java.util.List; 

import org.jetbrains.annotations.NotNull;
import org.jetbrains.annotations.Nullable;

/*
import com.ozforensics.liveness.sdk.actions.model.OzDataResponse;
import com.ozforensics.liveness.sdk.activity.CameraActivity;
import com.ozforensics.liveness.sdk.network.manager.NetworkManager;
import com.ozforensics.liveness.sdk.utility.enums.Action;
import com.ozforensics.liveness.sdk.utility.enums.OzApiRequestErrors;
import com.ozforensics.liveness.sdk.utility.enums.OzApiStatusVideoAnalyse;
import com.ozforensics.liveness.sdk.utility.enums.OzLocale;
import com.ozforensics.liveness.sdk.utility.enums.ResultCode;
import com.ozforensics.liveness.sdk.utility.managers.OzLivenessSDK;
import com.ozforensics.liveness.sdk.actions.model.OzMediaResponse;
import com.ozforensics.liveness.sdk.network.manager.UploadAndAnalyzeStatusListener;
import com.ozforensics.liveness.sdk.network.manager.LoginStatusListener;
import com.ozforensics.liveness.sdk.utility.enums.NetworkMediaTags;
import com.ozforensics.liveness.sdk.actions.model.LivenessCheckResult;
*/


import com.ozforensics.liveness.sdk.core.OzLivenessSDK;
import com.ozforensics.liveness.sdk.core.StatusListener;
import com.ozforensics.liveness.sdk.core.exceptions.OzException;
import com.ozforensics.liveness.sdk.core.model.OzAnalysisResult;
import com.ozforensics.liveness.sdk.core.model.OzMedia;
import com.ozforensics.liveness.sdk.core.model.OzMediaTag;

/**
 * This class echoes a string called from JavaScript.
 */
public class BiometricAuth extends CordovaPlugin {
	
	private CallbackContext mCallbackContext;
	private String path;
	
    /*private UploadAndAnalyzeStatusListener analyzeStatusListener = new UploadAndAnalyzeStatusListener() {

        @Override
        public void onSuccess(@NotNull List<LivenessCheckResult> result, @Nullable String stringInterpretation) {
            //if (stringInterpretation != null) showHint(stringInterpretation);
			mCallbackContext.success(stringInterpretation);
        }

        @Override
        public void onStatusChanged(@Nullable String status) {
            //if (status != null) showHint(status);			
        }

        @Override
        public void onError(@NotNull List<LivenessCheckResult> result, @NotNull String errorMessage) {
            //showHint(errorMessage);
			mCallbackContext.error(errorMessage);
        }
    }; */
	
	 private StatusListener<List<OzAnalysisResult>> analyzeStatusListener = new StatusListener<List<OzAnalysisResult>>() {
        @Override
        public void onSuccess(List<OzAnalysisResult> res) {
            StringBuilder resultString = new StringBuilder();
            for (int i = 0; i < res.size(); i++) {
                resultString.append(res.get(i).getType());
                resultString.append(" - ");
                resultString.append(res.get(i).getResolution());
                resultString.append("\n");
            }
            //showHint(resultString.toString());
			//mCallbackContext.success(resultString.toString());			
			mCallbackContext.success(res.get(0).getFolderId());
        }

        @Override
        public void onError(@NotNull OzException e) {
            //showHint(e.getMessage());
			mCallbackContext.error(e.getMessage());
        }


        @Override
        public void onStatusChanged(@Nullable String status) {
            //if (status != null) showHint(status);
        }
    };
	
	
	

    @Override
    public boolean execute(String action, JSONArray args, CallbackContext callbackContext) throws JSONException {
		mCallbackContext = callbackContext;
        if (action.equals("analyze")) {
            path = args.getString(0);
			String lang = args.getString(1);
            this.analyze(callbackContext, lang);
            return true;
        }
        return false;
    }

    private void analyze(CallbackContext callbackContext, String lang) {

		final CordovaPlugin that = this;
		
		/*LoginStatusListener loginStatusListener = new LoginStatusListener() {
            @Override
            public void onSuccess(@NotNull String token) {
                	List<OzLivenessSDK.OzAction> actions = new ArrayList<>();
					actions.add(OzLivenessSDK.OzAction.Smile);
					actions.add(OzLivenessSDK.OzAction.Scan);

					Intent intent = OzLivenessSDK.INSTANCE.createStartIntent(that.cordova.getActivity(), actions, 3, 3, true, null, null);
					that.cordova.startActivityForResult(that, intent, 5);
            }

            @Override
            public void onError(int errorCode, @NotNull String errorMessage) {
                callbackContext.error(errorMessage);
            }
        }; */
		
		StatusListener<String> loginStatusListener = new StatusListener<String>() {
            @Override
            public void onError(@NotNull OzException e) {
				callbackContext.error(e.getMessage());
            }

            @Override
            public void onStatusChanged(@Nullable String s) {

            }

            @Override
            public void onSuccess(@NotNull String token) {
                List<OzLivenessSDK.OzAction> actions = new ArrayList<>();
				actions.add(OzLivenessSDK.OzAction.Smile);
				actions.add(OzLivenessSDK.OzAction.Scan);

				Intent intent = OzLivenessSDK.INSTANCE.createStartIntent(that.cordova.getActivity(), actions);
				that.cordova.startActivityForResult(that, intent, 5);
            }
        };
		
		if(lang.equals("en")) {
			OzLivenessSDK.INSTANCE.setLocalizationCode(OzLivenessSDK.OzLocalizationCode.EN);
			//OzLivenessSDK.INSTANCE.setLocale(OzLocale.EN);
		} else if(lang.equals("ru")) {
			OzLivenessSDK.INSTANCE.setLocalizationCode(OzLivenessSDK.OzLocalizationCode.RU);
			//OzLivenessSDK.INSTANCE.setLocale(OzLocale.RU);
		} else {
			OzLivenessSDK.INSTANCE.setLocalizationCode(OzLivenessSDK.OzLocalizationCode.HY);
			//OzLivenessSDK.INSTANCE.setLocale(OzLocale.HY);
		}
		
		Context context = this.cordova.getActivity();
		String packageName = context.getPackageName();
		Resources resources = context.getResources();
		String api = context.getString(resources.getIdentifier("api_url", "string", packageName));
		String username = context.getString(resources.getIdentifier("username", "string", packageName));
		String password = context.getString(resources.getIdentifier("password", "string", packageName));
		OzLivenessSDK.INSTANCE.setBaseURL(api);
        OzLivenessSDK.INSTANCE.login(this.cordova.getActivity().getApplicationContext(), username, password, loginStatusListener);
    }
	
	@Override
	public void onActivityResult(int requestCode, int resultCode, Intent data) {
        //super.onActivityResult(requestCode, resultCode, data);

        String error = OzLivenessSDK.INSTANCE.getErrorFromIntent(data);
        List<OzMedia> sdkMediaResult = OzLivenessSDK.INSTANCE.getResultFromIntent(data);
		
		
        if (resultCode == -1) { // Ok Result
            uploadAndAnalyze(sdkMediaResult);
        } else if (resultCode == 0) { // Canceled Result
			mCallbackContext.error("canceled");
		}
    }
	
	private void uploadAndAnalyze(List<OzMedia> mediaList) {
        if (mediaList != null) {
			mediaList.add(new OzMedia(OzMedia.Type.PHOTO, path, OzMediaTag.PhotoIdFront));
            OzLivenessSDK.INSTANCE.uploadMediaAndAnalyze(
                    this.cordova.getActivity().getApplicationContext(),
                    mediaList,
                    analyzeStatusListener
            );
        }
    } 
}
