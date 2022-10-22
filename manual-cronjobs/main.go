package main

import (
	"context"
	"fmt"
	"os"
	"time"

	"github.com/google/uuid"
	batchv1 "k8s.io/api/batch/v1"
	corev1 "k8s.io/api/core/v1"
	"k8s.io/apimachinery/pkg/api/errors"
	metav1 "k8s.io/apimachinery/pkg/apis/meta/v1"
	"k8s.io/client-go/kubernetes"
	"k8s.io/client-go/tools/clientcmd"
)

func main() {
	kubeclient, err := getKubeClient()
	if err != nil {
		panic(err)
	}

	namespace := "default"
	cronjobName := "hello-world"
	ctx := context.Background()

	cj, err := assertCronjob(ctx, kubeclient, namespace, cronjobName)
	if err != nil {
		panic(err)
	}

	err = manuallyTriggerCronjobAndWait(ctx, kubeclient, namespace, cj)
	if err != nil {
		panic(err)
	}
}

func getKubeClient() (kubernetes.Interface, error) {
	homeDir, err := os.UserHomeDir()
	if err != nil {
		return nil, err
	}

	kubeConfigPath := fmt.Sprintf("%s/.kube/config", homeDir)
	cfg, err := clientcmd.BuildConfigFromFlags("", kubeConfigPath)
	if err != nil {
		return nil, err
	}

	kubeclient, err := kubernetes.NewForConfig(cfg)
	if err != nil {
		return nil, err
	}
	return kubeclient, nil
}

func assertCronjob(
	ctx context.Context,
	kubeclient kubernetes.Interface,
	namespace string,
	cronjobName string,
) (*batchv1.CronJob, error) {
	cronjobapi := kubeclient.BatchV1().CronJobs(namespace)

	cj, err := cronjobapi.Create(ctx, &batchv1.CronJob{
		ObjectMeta: metav1.ObjectMeta{
			Name:      cronjobName,
			Namespace: namespace,
		},
		Spec: batchv1.CronJobSpec{
			Schedule:                   "0 */10 * * *",
			SuccessfulJobsHistoryLimit: Int32(3),
			Suspend:                    Bool(false),
			JobTemplate: batchv1.JobTemplateSpec{
				Spec: batchv1.JobSpec{
					Template: corev1.PodTemplateSpec{
						Spec: corev1.PodSpec{
							RestartPolicy: corev1.RestartPolicyNever,
							Containers: []corev1.Container{
								{
									Name:            "hello-world",
									Image:           "alpine",
									ImagePullPolicy: corev1.PullIfNotPresent,
									Command: []string{
										"/bin/sh",
										"-c",
										`echo "Hello World"`,
									},
								},
							},
						},
					},
				},
			},
		},
	}, metav1.CreateOptions{})
	if err != nil && !errors.IsAlreadyExists(err) {
		return nil, err
	}
	if err != nil && errors.IsAlreadyExists(err) {
		cj, err := cronjobapi.Get(ctx, cronjobName, metav1.GetOptions{})
		if err != nil {
			return nil, err
		}
		return cj, nil
	}
	return cj, nil
}

func Int32(val int32) *int32 {
	return &val
}

func Bool(val bool) *bool {
	return &val
}

func manuallyTriggerCronjobAndWait(
	ctx context.Context,
	kubeclient kubernetes.Interface,
	namespace string,
	cronjob *batchv1.CronJob,
) error {
	job, err := manuallyTriggerCronjob(
		ctx,
		kubeclient,
		namespace,
		cronjob,
	)
	if err != nil {
		return err
	}
	return waitForJobCompletion(ctx, kubeclient, job)
}

func manuallyTriggerCronjob(
	ctx context.Context,
	kubeclient kubernetes.Interface,
	namespace string,
	cronjob *batchv1.CronJob,
) (*batchv1.Job, error) {
	jobspec := cronjob.Spec.JobTemplate.Spec

	jobapi := kubeclient.BatchV1().Jobs(namespace)
	job, err := jobapi.Create(ctx, &batchv1.Job{
		ObjectMeta: metav1.ObjectMeta{
			Namespace: namespace,
			Name:      fmt.Sprintf("%s-%s", cronjob.Name, uuid.New().String()),
			OwnerReferences: []metav1.OwnerReference{
				{
					APIVersion: "batch/v1", // this value is not populated by k8s client cronjob.APIVersion
					Kind:       "CronJob",  // this value is not populated by k8s client cronjob.Kind
					Name:       cronjob.Name,
					UID:        cronjob.UID,
				},
			},
		},
		Spec: jobspec,
	}, metav1.CreateOptions{})
	if err != nil {
		return nil, err
	}
	return job, nil
}

func waitForJobCompletion(
	ctx context.Context,
	kubeclient kubernetes.Interface,
	job *batchv1.Job,
) error {
	jobapi := kubeclient.BatchV1().Jobs(job.Namespace)

	watcher, err := jobapi.Watch(ctx, metav1.SingleObject(job.ObjectMeta))
	if err != nil {
		return err
	}

	defer watcher.Stop()

	for {
		select {
		case <-ctx.Done():
			return fmt.Errorf("request timeout reached")
		case <-time.After(3 * time.Minute):
			return fmt.Errorf("timeout reached waiting for job completion")
		case event := <-watcher.ResultChan():
			updatedJob, ok := event.Object.(*batchv1.Job)
			if !ok {
				return fmt.Errorf("couldn't cast event watcher object to job; object was %T", event.Object)
			}
			for _, condition := range updatedJob.Status.Conditions {
				if condition.Type == batchv1.JobComplete {
					return nil
				} else if condition.Type == batchv1.JobFailed {
					fmt.Println("job failed to complete successfully", condition.Message)
					return fmt.Errorf("job failed to complete successfully")
				}
			}
		}
	}
}
